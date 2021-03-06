require 'spec_helper'

share_examples_for :atomic do

  specify :test_construct do
    atomic = described_class.new
    atomic.value.should be_nil

    atomic = described_class.new(0)
    atomic.value.should eq 0
  end

  specify :test_value do
    atomic = described_class.new(0)
    atomic.value = 1

    atomic.value.should eq 1
  end

  specify :test_update do
    # use a number outside JRuby's fixnum cache range, to ensure identity is preserved
    atomic = described_class.new(1000)
    res = atomic.update {|v| v + 1}

    atomic.value.should eq 1001
    res.should eq 1001
  end

  specify :test_try_update do
    # use a number outside JRuby's fixnum cache range, to ensure identity is preserved
    atomic = described_class.new(1000)
    res = atomic.try_update {|v| v + 1}

    atomic.value.should eq 1001
    res.should eq 1001
  end

  specify :test_swap do
    atomic = described_class.new(1000)
    res = atomic.swap(1001)

    atomic.value.should eq 1001
    res.should eq 1000
  end

  specify :test_try_update_fails do
    # use a number outside JRuby's fixnum cache range, to ensure identity is preserved
    atomic = described_class.new(1000)
    expect {
      # assigning within block exploits implementation detail for test
      atomic.try_update{|v| atomic.value = 1001 ; v + 1}
    }.to raise_error(Concurrent::ConcurrentUpdateError)
  end

  specify :test_update_retries do
    tries = 0
    # use a number outside JRuby's fixnum cache range, to ensure identity is preserved
    atomic = described_class.new(1000)
    # assigning within block exploits implementation detail for test
    atomic.update{|v| tries += 1 ; atomic.value = 1001 ; v + 1}

    tries.should eq 2
  end

  specify :test_numeric_cas do
    atomic = described_class.new(0)

    # 9-bit idempotent Fixnum (JRuby)
    max_8 = 2**256 - 1
    min_8 = -(2**256)

    atomic.set(max_8)
    max_8.upto(max_8 + 2) do |i|
      atomic.compare_and_swap(i, i+1).should be_true, "CAS failed for numeric #{i} => #{i + 1}"
    end

    atomic.set(min_8)
    min_8.downto(min_8 - 2) do |i|
      atomic.compare_and_swap(i, i-1).should be_true, "CAS failed for numeric #{i} => #{i - 1}"
    end

    # 64-bit idempotent Fixnum (MRI, Rubinius)
    max_64 = 2**62 - 1
    min_64 = -(2**62)

    atomic.set(max_64)
    max_64.upto(max_64 + 2) do |i|
      atomic.compare_and_swap(i, i+1).should be_true, "CAS failed for numeric #{i} => #{i + 1}"
    end

    atomic.set(min_64)
    min_64.downto(min_64 - 2) do |i|
      atomic.compare_and_swap(i, i-1).should be_true, "CAS failed for numeric #{i} => #{i - 1}"
    end

    ## 64-bit overflow into Bignum (JRuby)
    max_64 = 2**63 - 1
    min_64 = (-2**63)

    atomic.set(max_64)
    max_64.upto(max_64 + 2) do |i|
      atomic.compare_and_swap(i, i+1).should be_true, "CAS failed for numeric #{i} => #{i + 1}"
    end

    atomic.set(min_64)
    min_64.downto(min_64 - 2) do |i|
      atomic.compare_and_swap(i, i-1).should be_true, "CAS failed for numeric #{i} => #{i - 1}"
    end

    # non-idempotent Float (JRuby, Rubinius, MRI < 2.0.0 or 32-bit)
    atomic.set(1.0 + 0.1)
    atomic.compare_and_set(1.0 + 0.1, 1.2).should be_true, "CAS failed for #{1.0 + 0.1} => 1.2"

    # Bignum
    atomic.set(2**100)
    atomic.compare_and_set(2**100, 0).should be_true, "CAS failed for #{2**100} => 0"

    # Rational
    require 'rational' unless ''.respond_to? :to_r
    atomic.set(Rational(1,3))
    atomic.compare_and_set(Rational(1,3), 0).should be_true, "CAS failed for #{Rational(1,3)} => 0"

    # Complex
    require 'complex' unless ''.respond_to? :to_c
    atomic.set(Complex(1,2))
    atomic.compare_and_set(Complex(1,2), 0).should be_true, "CAS failed for #{Complex(1,2)} => 0"
  end
end

module Concurrent

  describe Atomic do
    it_should_behave_like :atomic
  end

  describe MutexAtomic do
    it_should_behave_like :atomic
  end

  if defined? Concurrent::CAtomic
    describe CAtomic do
      it_should_behave_like :atomic
    end
  elsif defined? Concurrent::JavaAtomic
    describe JavaAtomic do
      it_should_behave_like :atomic
    end
  elsif defined? Concurrent::RbxAtomic
    describe RbxAtomic do
      it_should_behave_like :atomic
    end
  end

  describe Atomic do
    if TestHelpers.use_c_extensions?
      it 'inherits from CAtomic' do
        Atomic.ancestors.should include(CAtomic)
      end
    elsif TestHelpers.jruby?
      it 'inherits from JavaAtomic' do
        Atomic.ancestors.should include(JavaAtomic)
      end
    elsif TestHelpers.rbx?
      it 'inherits from RbxAtomic' do
        Atomic.ancestors.should include(RbxAtomic)
      end
    else
      it 'inherits from MutexAtomic' do
        Atomic.ancestors.should include(MutexAtomic)
      end
    end
  end
end
