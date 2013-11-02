require 'rebay'
require 'json'
require 'logger'

Rebay::Api.configure do |rebay|
  rebay.app_id = 'Twin-Dia-3f18-4f05-b81a-4ce4ba64f7a4'
end

shopping = Rebay::Shopping.new

#product = shopping.find_products(CategoryID: 11071, MaxEntries: 20, PageNumber: 1).results[5]
#
#p product
start = Time.now
p shopping.find_products({:'ProductID.Value' => 153165004, :'ProductID.type' => 'Reference', IncludeSelector: 'Items'}).results
#"231084801245\", \"321236146595\", \"161136253055\"


#shopping.get_multiple_items({ItemID: item_ids.take(5).join(','), IncludeSelector: 'ItemSpecifics'}).results.each do |item|
#  list = item['ItemSpecifics']['NameValueList'] rescue next
#  p list.select { |x| x['Name'] == 'Brand' }.first['Value'] rescue p 'No Brand'
#  p list.select { |x| x['Name'] == 'Model' }.first['Value'] rescue p 'No Model'
#end
#
#p Time.now - start

#p productDetails


#p shopping.get_single_item({ItemID: 261312667134, IncludeSelector: 'ItemSpecifics'})