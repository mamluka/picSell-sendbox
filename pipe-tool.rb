#!/usr/bin/env ruby

require 'pry'
require 'thor'
require 'json'
require 'digest/md5'
require 'logger'

require_relative 'extentions'

class Pipe < Thor

  def initialize(*args)
    super

    @pipe_data = YAML.load File.read(File.dirname(__FILE__) +'/pipes-data.yml')
    @logger = Logger.new('log-pipe.log')
  end

  desc 'combine', 'combine files to a grouped by'
  option :min_price, default: 50, type: :numeric

  def combine(ebay_file, amazon_file, matched_file)
    ebay_products = json_load ebay_file
    amazon_products = json_load amazon_file
    matched_pairs = json_load matched_file

    combined_products = matched_pairs.select { |x| x[:matched] }.map { |x|
      asin = x[:asin]
      upc = x[:query]

      ebay_product = ebay_products.select { |p| p[:properties][:upc] && p[:properties][:upc].include?(upc) }.first
      next if ebay_product.nil?

      amazon_product = amazon_products.select { |p| p[:asin] == asin }.first
      next if amazon_product.nil?

      {
          name: ebay_product[:name],
          amazon_name: amazon_product[:original_name],
          ebay_name: ebay_product[:original_name],
          asin: asin,
          upc: upc,
          amazon: amazon_product,
          ebay: ebay_product
      }
    }
    .compact
    .group_by { |x| x[:name] }
    .map { |k, v|
      {
          name: k,
          products: v

      }
    }

    $stdout.puts JSON.pretty_generate(combined_products)

  end

  desc 'mash', 'Mash amazon and ebay together'

  def mash(file, category)

    data = @pipe_data[category.to_sym]

    products = json_load file

    mashed_products = products.map { |x|
      begin
        variants = x[:products].map { |p|

          basic = {
              name: p[:name],
              amazon_name: p[:amazon_name],
              ebay_name: p[:ebay_name],
              asin: p[:asin],
              upc: p[:upc],
              item_count: p[:ebay][:item_count] + p[:amazon][:item_count],
              sales_rank: (1.0/p[:amazon][:sales_rank])*10000,
          }

          prices = Hash.new
          prices[:ebay_new] = p[:ebay][:price][:new]
          prices[:ebay_used] = p[:ebay][:price][:used]
          prices[:amazon_new] = p[:amazon][:price][:new] if p[:amazon][:price][:new]
          prices[:amazon_used] = p[:amazon][:price][:used] if p[:amazon][:price][:used]

          prices[:new] = [prices[:ebay_new], prices[:amazon_new]].compact.min
          prices[:used] = [prices[:ebay_used], prices[:amazon_used]].compact.min

          basic[:prices] = prices

          basic[:variants] = Hash[data[:variants].map { |v|
            [v, p[:ebay][:properties][v]] if p[:ebay][:properties][v]
          }.compact]

          basic[:properties] = p[:ebay][:properties].merge(p[:amazon][:properties])

          basic
        }

        {
            id: Digest::MD5.hexdigest(x[:name])[0..8],
            name: x[:name],
            item_count: variants.inject(0) { |sum, x| sum + x[:item_count] },
            sales_rank: variants.inject(0) { |sum, x| sum + x[:sales_rank] },
            variants_count: variants.length,
            category: category,
            variants: variants

        }
      rescue Exception => ex

      end
    }

    $stdout.puts JSON.pretty_generate mashed_products

  end

  private

  def json_load(file)
    JSON.parse File.read(file), symbolize_names: true
  end
end

Pipe.start