require 'rebay'
require 'json'
require 'logger'

Rebay::Api.configure do |rebay|
  rebay.app_id = 'Twin-Dia-3f18-4f05-b81a-4ce4ba64f7a4'
end

logger = Logger.new(STDOUT)

finder = Rebay::Shopping.new
products = Array.new

File.readlines('brands').each do |brand|
  brand = brand.strip

  logger.info "Start looking for #{brand}"
  response = finder.find_popular_items({CategoryID: 31388, QueryKeywords: brand, MaxEntries: 100})

  next if response.results.nil?

  logger.info "Found #{response.results.length} results"

  response.results.each do |r|
    next if !r.kind_of?(Hash) || !r.has_key?('Title')
    products << {name: r['Title']}
  end

end

File.open('camera-ebay-products.json', 'w') { |f| f.write JSON.pretty_generate(products) }
