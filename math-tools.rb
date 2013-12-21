class MathTools
  def self.analyze(array)
    return nil if array.length == 0

    total = array.inject(:+)
    len = array.length
    sorted = array.sort
    median = len % 2 == 1 ? sorted[len/2] : (sorted[len/2 - 1] + sorted[len/2]).to_f / 2

    {
        lowest: array.min,
        highest: array.max,
        count: array.length,
        average: total.to_f / len,
        median: median,
    }

  end

  def self.percent_range(value, range)
    [(value*(1-range)).round(0), (value*(1+range)).round(0)]
  end

  def self.deviation_warning(first, second, tolerance)
    ratio = ((first/second)*100).round(0)

    if (ratio) < (100-tolerance) || (ratio) > (100+tolerance)
      (ratio-100).abs
    else
      nil
    end
  end
end

