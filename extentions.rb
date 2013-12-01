class NilClass
  def empty_if_nil
    []
  end
end

class Array
  def empty_if_nil
    self
  end
end

class Hash
  def empty_if_nil
    self
  end
end