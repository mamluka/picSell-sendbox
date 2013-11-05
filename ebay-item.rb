require 'rebay'
require 'json'
require 'logger'
require 'rest-client'
require 'peach'

Rebay::Api.configure do |rebay|
  rebay.app_id = 'Twin-Dia-3f18-4f05-b81a-4ce4ba64f7a4'
end

shopping = Rebay::Shopping.new
finder = Rebay::Finding.new
#response = shopping.find_popular_items({CategoryID: 31388, QueryKeywords: 'canon', MaxEntries: 100})

#item_id = response.results.first['ItemID']

products = Array.new
start = Time.now

product_ranking = Hash.new

(1..200).peach(10) do |page|
  current_page = page
  response = shopping.find_products(CategoryID: 9355, MaxEntries: 20, PageNumber: current_page, IncludeSelector: 'Details')

  next if response.results.nil?

  results = response.results

  results.each_index { |i| product_ranking[results[i]['ProductID']['Value']] = (10000-((current_page-1)*20+i+1)) }

  results.peach(10) do |x|
    response = RestClient.get x['DetailsURL']


    response = response.force_encoding('utf-8')

    product_id = x['ProductID']['Value']

    brand = response.scan(/>Brand.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil
    model = response.scan(/>Model.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil
    family_line = response.scan(/>Family Line.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil
    carrier = response.scan(/>Carrier.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil
    storage_capacity = response.scan(/>Storage Capacity.+?<font.+?>(.+?)<\/font>/)[0][0] rescue nil

    family_line = family_line.gsub(brand, '') if !brand.nil? && !family_line.nil?

    name = "#{brand} #{family_line} #{model} #{storage_capacity}".squeeze(' ').strip

    average_price = nil

    items_by_product = finder.find_items_by_product({productId: product_id, :'itemFilter.name' => 'ListingType', :'itemFilter.value' => 'AuctionWithBIN'}).results

    if not items_by_product.nil?
      groups = find_items.results.group_by { |x| x['condition']['conditionId'].to_i }

      new_items = groups
      .select { |k| k < 2000 }
      .map {|k,v| v}
      .flatten
      .map { |x| x['listingInfo']['buyItNowPrice']['__value__'].to_i if x.kind_of?(Hash) && x.has_key?('listingInfo') && x['listingInfo'].has_key?('buyItNowPrice') }
      .select { |x| !x.nil? }

      used_items = groups
      .select { |k| k == 3000 }
      .map {|k,v| v}
      .flatten
      .map { |x| x['listingInfo']['buyItNowPrice']['__value__'].to_i if x.kind_of?(Hash) && x.has_key?('listingInfo') && x['listingInfo'].has_key?('buyItNowPrice') }
      .select { |x| !x.nil? }

      used_items.each {|x| $stdout.puts x }

      ebay = {
             new
      }

      MathTools.analyze new_items
      p MathTools.analyze used_items
    end

    products << {
        name: name,
        details_url: x['DetailsURL'],
        product_id: product_id,
        model: model,
        brand: brand,
        family_line: family_line,
        carrier: carrier,
        storage_capacity: storage_capacity,
        average_price: average_price,
        popularity_rank: product_ranking[product_id],
        item_count: (items_by_product.length rescue nil)

    }

  end


end

p Time.now-start
products = products.uniq { |x| x[:name] }

$stdout.puts products.length

File.open('phones-ebay-products.json', 'w') { |f| f.write JSON.pretty_generate(products) }