require 'rebay'
require 'json'
require 'logger'

Rebay::Api.configure do |rebay|
  rebay.app_id = 'Twin-Dia-3f18-4f05-b81a-4ce4ba64f7a4'
end

shopping = Rebay::Shopping.new
response = shopping.find_popular_items({CategoryID: 31388, QueryKeywords: 'canon', MaxEntries: 100})

item_id = response.results.first['ItemID']

p shopping.get_single_item({ItemID: 200976446842,IncludeSelector:'ItemSpecifics'}).results