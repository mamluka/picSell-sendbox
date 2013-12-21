#!/usr/bin/env ruby

require 'tire'
require 'json'
require 'digest/md5'
require 'thor'

class ProductIndexing < Thor
  desc 'index', 'Index the json files'
  option :delete_index, type: :boolean

  def index(file)
    delete_index = options[:delete_index]
    products = json_load file

    Tire.index 'products' do
      delete if delete_index
      bulk :index, products.map { |x|
        x[:_id] = x[:id]
        x
      }
    end

  end

  desc 'Delete the index', 'Delete the index in elastic search'

  def delete_index
    Tire.index 'products' do
      delete
    end
  end

  private

  def json_load(file)
    JSON.parse File.read(file), symbolize_names: true
  end
end

ProductIndexing.start