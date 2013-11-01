require 'tire'
require 'json'

Tire.index 'products' do
  delete
  create :mappings => {
      :product => {
          :properties => {
              suggest: {type: 'completion',
                        index_analyzer: 'simple',
                        search_analyzer: 'simple',
                        preserve_position_increments: false,
                        payloads: true,
                        max_input_len: 2000
              }
          }
      }
  }
end

products = JSON.parse(File.read('ebay-products.json'), :symbolize_names => true)

products.each do |p|
  input = p[:name].split(' ')
#  input << p[:model] if not p[:model].nil?

  more = {
      suggest: {
          input: input,
          output: p[:name],
      },
      _type: 'product'
  }

  p.merge!(more)
end

p products

Tire.index 'products' do
  bulk :index, products
end
