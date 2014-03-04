require 'rspec'

describe 'RSpecEqual' do
  it 'checks equality' do
    1.should equal(1)
  end
end

30.times do |i|
  describe "RSpecSleep(#{i})" do
    it "sleeps" do
      start = Time.now
      sleep(0.25)
      (Time.now-start).should be_within(0.02).of(0.25)
    end
  end
end

describe 'RSpecFailure' do
  it 'fails' do
    :foo.should eq(:bar)
  end
end
