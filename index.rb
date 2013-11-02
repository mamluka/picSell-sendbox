require 'tire'
require 'json'

class TvELT
  def self.clean(name)
    try_match = name.scan(/^.+?"/)[0]
    return try_match if not try_match.nil?

    name
  end
end

Tire.index 'products' do
  delete
  create :mappings => {
      :product => {
          :properties => {
              suggest: {type: 'completion',
                        index_analyzer: 'keyword',
                        search_analyzer: 'keyword',
                        preserve_position_increments: false,
                        payloads: true,
                        max_input_len: 2000
              },
              name: { :type => 'string', :analyzer => 'keyword'}
          }
      }
  }
end

products = JSON.parse(File.read('tv-ebay-products.json'), :symbolize_names => true)

products.each do |p|
  name = TvELT.clean p[:name]

  input = name.split(' ').select { |word| word.length > 2 }.map { |word| word.downcase }
  input << p[:model] if not p[:model].nil?


  more = {
      suggest: {
          input: input.uniq,
          output: name,
      },
      _type: 'product'
  }

  p.merge!(more)
end

Tire.index 'products' do
  bulk :index, products
end
