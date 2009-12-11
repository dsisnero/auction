require 'rubygems'
require 'fastercsv'
require 'tempfile'
require 'open-uri'
require 'ruby-debug'
require 'nokogiri'
require 'datamapper'



class Auction

  include DataMapper::Resource

  property :lot, String
  property :inv, String
  property :description, :Text
  

end


class Product

  include DataMapper::Resource

  property :name, String
  property :manufacturer, String
  property :upc, String
  property :price, String


end
  
  
class Parser

  attr_accessor :lot,:inv,:description

  def initialize(lot,inv,description)
    @lot, @inv,@description = lot,inv,description
  end

  def to_s
    "%s\t\%s\t%s" % [lot,inv,description]
  end

  def to_a
    [lot,inv,description]
  end  

end



  #attr_reader :products

  def initialize(file)
    @file = file    
    @products = []
  end

  def parse(filename = @file)
    header = /Lot(\ ){3,}Inv#(\ ){3,}Description/
      blank_line = /^\s*$/
    File.open(filename) do |file|
      @products = []
      col2_products = []
      current_lot = 0
      line = file.gets until line =~ header
      file.each do |line|
        next if line =~ blank_line
        next if line == "\f"
        if line =~ header
          add_col2_products(col2_products)
          col2_products = []
          next
        end
        array_of_two_products = split_line(line)
        col1_prod,col2_prod = separate_columns(array_of_two_products)
        col2_products << col2_prod if col2_prod
        add_product(col1_prod)
      end
      add_col2_products(col2_products)
    end
  end

  def add_col2_products(col2_array)
    until col2_array.empty?
      add_product(col2_array.shift)
    end
  end

  def split_line(line)
    line.chomp.split(/\ {3,}/)
  end
  

  def add_product(product)
    if product.lot == ""
      product.lot = current_lot
    end
    if @products.empty?
      @products << product
    else
      debugger  if (product.lot != current_lot) && (product.lot != next_lot)
      @products << product
    end
  end    

  def current_lot
    @products.empty? ? 0 : @products.last.lot
  end

  def next_lot
    lot,number = current_lot.match(lot_regex).captures rescue debugger
    numarray = number.scan(/\d/)
    numarray.shift until numarray[0] != "0"
    number = numarray.join()
    number = Integer(number) + 1 rescue debugger
    number_part = ("%3d" % [number]).gsub(" ","0")
    "#{lot}#{number_part}"    
  end

  def lot_regex
    @lot_reg ||= /([^\d]+)(\d+)/
  end
  

  def products
    parse if @products.empty?
    @products
  end

  def separate_columns(array)
    lot,inv,desc = array[0...3]
    unless lot 
      lot = products.pop.lot
    end
    prod1 = Product.new(lot,inv,desc)
    product2 = array[3..-1]
    # debugger if product2.include?("43471")
    
    if product2.empty?
      prod2 = nil
    else
      if product2.size == 3
        lot2,inv2,desc2 = product2
        
      elsif product2[0] =~ /B\d{3}/
        lot2,inv2 = product2
        desc2 = ""
      else
        inv2,desc2 = product2
        lot2 = ""
      end    
      prod2  =  Product.new(lot2,inv2,desc2)
    end
    return [prod1,prod2]
  end


  def save(name)
    
  end


end


class App

  require 'fileutils'
  require 'open-uri'
  include FileUtils::Verbose

  attr_reader :pdf_name

  def initialize()
    @host = 'http://bulward.com'
  end

  def doc
    @doc ||= Nokogiri::HTML(open('http://bulward.com/auctionschedule.html'))
  end

  def get_pdf_nodes()
     doc.css('a:match_href("lotlist")', Class.new{
              def match_href list, expression
                list.find_all{|node| node['href'] =~ /#{expression}/}
              end
            }.new)
  end

  def auction_name(node)
    node.parent.css('strong').map{|node| node.content}.join('.').gsub(/,| /,'.').squeeze('.')
  end


  def out_name(pdf_name)
    File.basename(pdf_name, '.pdf') + '.csv'
  end

  def dir_name(pdf_name)
    File.basename(pdf_name, '.pdf')
  end

  def run
    pdf_nodes = get_pdf_nodes
    #urls = pdf_nodes.map{|node| File.join(@host,node['href'])}
    pdf_nodes.each do |node|
      name = auction_name(node)
      mkdir name
      cd name do
        pdf_name = name + '.pdf'
        url = File.join(@host, node['href'])
        File.open(pdf_name,'w') do |pdf|
          pdf.write open(url).read
        end
        txt_file = convert_pdf(pdf_name)
        products = parse(txt_file)
        save_as_csv(out_name(pdf_name),products)
        photo_url = full_path(find_photo_url(node))
        mkdir 'images'
        cd 'images' do
          get_photos(photo_url)
        end
      end
    end
  end

  def find_photo_url(node)
    current = node
    loop do
      current = current.next
      break if current.name == 'a'
    end
    current['href']
  end
  

  def convert_pdf(pdf_name)
    txt_file = Tempfile.new(File.basename(pdf_name))   
    cmd = "pdftotext -layout #{pdf_name} #{txt_file.path}"
    puts "Running #{cmd}"
    system(cmd)
    txt_file.close
    txt_file
  end

  def parse(txt_file)    
    parser = Parser.new(txt_file.path)
    parser.products
  end

  def products
    @parser.products
  end

  def save_as_csv(name,products)
    #  debugger
    FasterCSV.open(name, "w") do |csv|
      products.each do |product|
        csv << product.to_a
      end
    end
  end

  def full_path(partial_url)
    File.join(@host, partial_url)
  end
  

  def get_photos(url)
    puts "Getting Photos\n"
    photodoc = Nokogiri::HTML(open(url))
    #debugger
    photo_links = photodoc.css('a').select{|node| node['href'] =~ /photoshow\d*\.cfm\?Number=/}
    tiny_src = photo_links.map{|link| link.at('img')['src']}
    sources = tiny_src.map{|src| src.sub('T_',"")}
    sources.each do |src|
      photo_path = full_path(src)
      puts "Getting #{photo_path}" if $DEBUG
      open(photo_path) do |infile|
        File.open(File.basename(photo_path),'w'){|f| f.write infile.read}
      end
    end
  end
end







if $0 == __FILE__
  
  
  app = App.new
  
  
  
  app.run
  

  # parser = Parser.new('8.22.lotlist.txt')
  #parser.save('8.22.lotlist.csv')
end

