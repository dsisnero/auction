

### MODELS
class Product
  include DataMapper::Resource
  property :id,         Integer, :serial=>true
  property :description,      String
  property :manufacuturer, String
  property :model, String
  property :upc, String
  property :price, Float
  property :created_at, DateTime
  property :complete,   Boolean, :default=>false

  #validates_present :title
end

class Lot
  
  include DataMapper::Resource
  property :id, Integer, :serial => true
  property :lot, String

  

end
