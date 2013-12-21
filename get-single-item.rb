require 'rebay'
require 'json'
require 'logger'

Rebay::Api.configure do |rebay|
  rebay.app_id = 'Twin-Dia-3f18-4f05-b81a-4ce4ba64f7a4'
end

shopping = Rebay::Shopping.new

response = shopping.get_single_item(ItemID: ARGV[0])

$stdout.puts response.response
