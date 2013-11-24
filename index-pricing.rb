require 'tire'
require 'json'

products = JSON.parse(File.read(ARGV[0]), :symbolize_names => true)

Tire.index 'products' do
  delete
  bulk :index, products
end
