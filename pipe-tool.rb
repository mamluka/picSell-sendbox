#!/usr/bin/env ruby

require 'pry'
require 'thor'
require 'json'
require 'digest/md5'
require 'logger'

require_relative 'extentions'

module Core
  module Mapping
    class Mapping

      def initialize
        @mapping = YAML.load File.read(File.dirname(__FILE__)+'/properties-mapping.yml')
      end

      def map(properties)
        Hash[@mapping[:definitions].map { |k, v|
          [k, [*v].map { |p| [*p].inject(properties) { |sum, x| sum[x.to_sym] if !sum.nil? && sum.kind_of?(Hash) } }.compact.first]
        }.select { |k, v| !v.nil? }]
      end

    end
  end
end

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

    combined_products = matched_pairs
    .select { |x| x[:matched] }
    .map { |x|
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
          variant_id: Digest::MD5.hexdigest("#{asin}#{upc}")[0..8],
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

      product_id =Digest::MD5.hexdigest(x[:name])[0..8]
      variants = x[:products].map { |p|

        basic = {
            name: p[:name],
            long_name: p[:ebay_name],
            description: p[:ebay][:description],
            amazon_name: p[:amazon_name],
            ebay_name: p[:ebay_name],
            asin: p[:asin],
            upc: p[:upc],
            category: category,
            variant_id: p[:variant_id],
            product_id: product_id,
            item_count: p[:ebay][:item_count] + p[:amazon][:item_count],
            sales_rank: (1.0/p[:amazon][:sales_rank])*10000,
        }

        prices = Hash.new

        if p[:ebay][:price]
          prices[:ebay_new] = p[:ebay][:price][:new] if p[:ebay][:price][:new]
          prices[:ebay_used] = p[:ebay][:price][:used] if p[:ebay][:price][:used]
        end

        if p[:amazon][:price]
          prices[:amazon_new] = p[:amazon][:price][:new] if p[:amazon][:price][:new]
          prices[:amazon_used] = p[:amazon][:price][:used] if p[:amazon][:price][:used]
        end

        prices[:new] = [prices[:ebay_new], prices[:amazon_new]].compact.min
        prices[:used] = [prices[:ebay_used], prices[:amazon_used]].compact.min

        basic[:prices] = prices

        basic[:variants] = Hash[data[:variants].map { |v|
          [v, p[:ebay][:properties][v]] if p[:ebay][:properties][v]
        }.compact]

        mapping = Core::Mapping::Mapping.new
        properties = convert_keys_to_symbols(p[:amazon][:raw_properties].merge(p[:ebay][:properties]))

        basic[:properties] = mapping.map(properties)

        basic
      }.uniq { |x| x[:variants] }

      {
          id: product_id,
          name: x[:name],
          item_count: variants.inject(0) { |sum, x| sum + x[:item_count] },
          sales_rank: variants.inject(0) { |sum, x| sum + x[:sales_rank] },
          variants_count: variants.length,
          category: category,
          variants: variants

      }
    }

    $stdout.puts JSON.pretty_generate mashed_products

  end

  private

  def json_load(file)
    JSON.parse File.read(file), symbolize_names: true
  end

  def convert_keys_to_symbols(hash)
    s2s =
        lambda do |h|
          Hash === h ?
              Hash[
                  h.map do |k, v|
                    [k.respond_to?(:to_sym) ? k.to_sym : k, s2s[v]]
                  end
              ] : h
        end

    s2s[hash]
  end

end

Pipe.start