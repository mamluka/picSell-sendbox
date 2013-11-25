require 'json'
require 'yaml'
require 'pry'

category_id = ARGV[0].to_sym

amazon_etl = YAML.load(File.read(File.dirname(__FILE__) + '/amazon-etl.yml'))
products = JSON.parse File.read("amazon-#{ARGV[0]}.json"), symbolize_names: true

products = products
.group_by { |x| x[:name] }
.map { |k, v|

  first_product = v.first

  base_hash = {
      name: first_product[:name],
      brand: first_product[:brand],
      model: first_product[:model],
      item_count: v.inject(0) { |sum, x| sum+x[:item_count] },
      sales_rank: v.inject(0) { |sum, x| sum+x[:sales_rank] } / v.length,
  }

  variants = amazon_etl[category_id][:variants]
  keys = variants.map { |x| x[:key] }

  products_that_are_variants = v.select { |x| keys.all? { |k| x.has_key? k } }
  products_that_are_variants = products_that_are_variants.uniq { |x| keys.map { |k| x[k] }.join('::') }

  products = Array.new
  if products_that_are_variants.length > 1
    base_hash[:variants] = variants.map { |x|
      {
          name: x[:name],
          values: products_that_are_variants.map { |p| p[x[:key]] }
      }
    }

    base_hash[:products] = products_that_are_variants
  else
    base_hash[:products] = [v.first]
  end

  base_hash
}

File.open("amazon-#{ARGV[0]}-compact.json", 'w') { |f| f.write JSON.pretty_generate(products) }