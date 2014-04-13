require 'minitest/spec'

class Meme
  def i_can_has_cheezburger?
    "OHAI!"
  end

  def will_it_blend?
    "YES!"
  end
end

describe Meme do
  before do
    @meme = Meme.new
  end

  describe "when asked about cheeseburgers" do
    it "must respond positively" do
      sleep 0.1
      @meme.i_can_has_cheezburger?.must_equal "OHAI!"
    end
  end

  describe "when asked about blending possibilities" do
    it "won't say no" do
      sleep 0.1
      @meme.will_it_blend?.wont_match /^no/i
    end
  end

  describe "when testing something futile" do
    it "will always fail" do
      assert false, "always fails"
    end
  end

  describe "when testing something erroneous" do
    it "will always error" do
      errorfunction
    end
  end

end
