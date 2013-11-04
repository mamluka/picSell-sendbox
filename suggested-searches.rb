require 'rebay'
require 'json'
require 'logger'

Rebay::Api.configure do |rebay|
  rebay.app_id = 'Twin-Dia-3f18-4f05-b81a-4ce4ba64f7a4'
end

shopping = Rebay::Shopping.new

p shopping.find_popular_searches({CategoryID: 9355, IncludeChildCategories: true,MaxKeywords:100})