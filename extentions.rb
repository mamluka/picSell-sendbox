require 'json'

class NilClass
  def empty_if_nil
    []
  end
end

class Array
  def empty_if_nil
    self
  end

  def remove_growth_over(limit)
    self.select! { |x| x > 0 }

    return [] if self.empty?
    self.zip(self.drop(1).insert(self.length-1, self.last)).map { |x| [x[1], x[1]/x[0].to_f] }.take_while { |x| x[1] <= limit }.map { |x| x[0] }.insert(0, self[0])
  end
end

class Hash
  def empty_if_nil
    self
  end
end

class NilClass
  def zero_if_nil
    0
  end
end

class Fixnum
  def zero_if_nil
    self
  end
end

class Float
  def zero_if_nil
    self
  end
end

class String
  def parse_path_to_json
    JSON.parse File.read(self), symbolize_names: true
  end
end