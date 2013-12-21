#!/usr/bin/env ruby

require 'pry'
require 'thor'
require 'json'

require_relative 'extentions'

class Curating < Thor
  desc 'prices', 'Extract price data into a csv'
  option :min_price, default: 50, type: :numeric

  def prices(file)
    products = JSON.parse File.read(file), symbolize_names: true

    products
    .select { |x| x[:products].length == 1 }
    .each { |x|
      prices = [x[:products][0][:price][:new].zero_if_nil, x[:products][0][:price][:used].zero_if_nil]
      next if prices.min < options[:min_price]

      $stdout.puts [x[:id],prices].flatten.join(',')
    }
  end
end

Curating.start