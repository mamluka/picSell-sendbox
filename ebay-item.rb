require 'rebay'
require 'json'
require 'logger'
require 'rest-client'
require 'peach'

Rebay::Api.configure do |rebay|
  rebay.app_id = 'Twin-Dia-3f18-4f05-b81a-4ce4ba64f7a4'
end

shopping = Rebay::Shopping.new
#response = shopping.find_popular_items({CategoryID: 31388, QueryKeywords: 'canon', MaxEntries: 100})

#item_id = response.results.first['ItemID']
products = Array.new
start = Time.now

(1..500).peach(8) do |page|
  response = shopping.find_products(CategoryID: 11071, MaxEntries: 20, PageNumber: page)
  next if response.results.nil?

  response.results.peach(8) do |x|
    response = RestClient.get x['DetailsURL']

    response  = response.force_encoding('utf-8')

    brand = response.scan(/>Brand.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil
    model = response.scan(/>Model.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil

    products << {
        name: x['Title'],
        details_url: x['DetailsURL'],
        product_id: x['ProductID'],
        model: model,
        brand: brand
    }

  end


end
p Time.now-start

$stdout.puts products.length

File.open('tv-ebay-products.json', 'w') { |f| f.write JSON.pretty_generate(products) }