class EbayTabletsShortDisplaySize
  def calculate(input)
    input.scan(/\d+\.?\d+?in/)[0]
  end
end

class EbayTabletsInchCountDisplaySize
  def calculate(input)
    match = input.scan(/(\d+\.?\d+?)in/)[0]
    match.nil? ? nil : match[0]
  end
  end

class EbayTabletsCleanCarrier
  def calculate(input)
    input.gsub('(US)','').strip
  end
end