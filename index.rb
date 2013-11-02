require 'tire'
require 'json'

class TvELT
  def self.clean(name)
    try_match = name.scan(/^.+?"/)[0]
    return try_match if not try_match.nil?

    name
  end
end

class PhoneELT
  def self.clean(name)
    try_match = name.scan(/(^.+?)\s-/)[0]
    return try_match[0] if not try_match.nil?

    name
  end

  def self.input (name)
    terms = Array.new

    name.split(' ')
    .map { |word| word.downcase }
    .inject { |sum, x|
      sum = sum + ' ' + x
      terms << sum
      sum
    }

    terms.uniq
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
              name: {:type => 'string', :analyzer => 'keyword'}
          }
      }
  }
end

products = JSON.parse(File.read('phones-ebay-products.json'), :symbolize_names => true)

products.each do |p|
  name = PhoneELT.clean p[:name]

  input = PhoneELT.input name
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
