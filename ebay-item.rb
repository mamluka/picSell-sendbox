require 'rebay'
require 'json'
require 'logger'

Rebay::Api.configure do |rebay|
  rebay.app_id = 'Twin-Dia-3f18-4f05-b81a-4ce4ba64f7a4'
end

shopping = Rebay::Shopping.new
#response = shopping.find_popular_items({CategoryID: 31388, QueryKeywords: 'canon', MaxEntries: 100})

#item_id = response.results.first['ItemID']
products = Array.new
start = Time.now

(1..500).each do |page|
  response = shopping.find_products(CategoryID: 31388, MaxEntries: 20, PageNumber: page)
  response.results.each do |x|
    products << x["Title"]
  end

  $stdout.puts products.length
end

p Time.now-start

File.open('ebay-products.json', 'w') { |f| f.write JSON.pretty_generate(products) }
