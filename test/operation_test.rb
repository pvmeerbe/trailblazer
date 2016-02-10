require "test_helper"

module Inspect
  def inspect
    "<#{self.class.to_s.split("::").last} @model=#{@model}>"
  end
  alias_method :to_s, :inspect
end

class OperationSetupParamsTest < MiniTest::Spec
  class OperationSetupParam < Trailblazer::Operation
    def process(params)
      @model = params
    end

    def setup_params!(params)
      params.merge!(garrett: "Rocks!")
    end

    include Inspect
  end

  # allows you changing params in #setup_params!.
  it { OperationSetupParam.run({valid: true}).to_s.must_equal "[true, <OperationSetupParam @model={:valid=>true, :garrett=>\"Rocks!\"}>]" }
end

class OperationParamsTest < MiniTest::Spec
  class Operation < Trailblazer::Operation
    def process(params)
      @model = "#{params} and #{@params==params}"
    end

    def params!(params)
      { params: params }
    end
  end

  # allows you returning new params in #params!.
  it { Operation.({valid: true}).model.to_s.must_equal "{:params=>{:valid=>true}} and true" }
end

# Operation#model.
class OperationModelTest < MiniTest::Spec
  class Operation < Trailblazer::Operation
    def process(params)
    end

    def model!(params)
      params
    end
  end

  # #model.
  it { Operation.(Object).model.must_equal Object }
end

# Operation#model=.
class OperationModelEqualsTest < MiniTest::Spec
  class Operation < Trailblazer::Operation
    def process(params)
      self.model = "#{params} and #{@params==params}"
    end

    def params!(params)
      { params: params }
    end
  end

  # allows you returning new params in #params!.
  it { Operation.("I can set @model via a private setter").model.to_s.must_equal "{:params=>\"I can set @model via a private setter\"} and true" }
end

class OperationRunTest < MiniTest::Spec
  class Operation < Trailblazer::Operation
    # allow providing your own contract.
    self.contract_class = class Contract
      def initialize(*)
      end
      def validate(params)
        return true if params == "yes, true"
        false
      end

      def errors
        Struct.new(:to_s).new("Op just calls #to_s on Errors!")
      end
      self
    end

    def process(params)
      model = Object
      validate(params, model)
    end

    include Inspect
  end

  # contract is inferred from self::contract_class.
  # ::run returns result set when run without block.
  it { Operation.run("not true").to_s.must_equal %{[false, <Operation @model=>]} }
  it { Operation.run("yes, true").to_s.must_equal %{[true, <Operation @model=>]} }

  # ::call raises exception when invalid.
  it do
    exception = assert_raises(Trailblazer::Operation::InvalidContract) { Operation.("not true") }
    exception.message.must_equal "Op just calls #to_s on Errors!"
  end

  # return operation when ::call
  it { Operation.("yes, true").to_s.must_equal %{<Operation @model=>} }
  # #[] is alias for .()
  it { Operation["yes, true"].to_s.must_equal %{<Operation @model=>} }


  # ::run with block returns operation.
  # valid executes block.
  it "block" do
    outcome = nil
    res = Operation.run("yes, true") do
      outcome = "true"
    end

    outcome.must_equal "true" # block was executed.
    res.to_s.must_equal %{<Operation @model=>}
  end

  # invalid doesn't execute block.
  it "block, invalid" do
    outcome = nil
    res = Operation.run("no, not true, false") do
      outcome = "true"
    end

    outcome.must_equal nil # block was _not_ executed.
    res.to_s.must_equal %{<Operation @model=>}
  end

  # block yields operation
  it do
    outcome = nil
    res = Operation.run("yes, true") do |op|
      outcome = op
    end

    outcome.to_s.must_equal %{<Operation @model=>} # block was executed.
    res.to_s.must_equal %{<Operation @model=>}
  end

  # # Operation#contract returns @contract
  it { Operation.("yes, true").contract.class.to_s.must_equal "OperationRunTest::Operation::Contract" }




  describe "::present" do
    class NoContractOp < Trailblazer::Operation
      self.contract_class = nil

      def model!(*)
        Object
      end
    end

    # the operation and model are available, but no contract.
    it { NoContractOp.present({}).model.must_equal Object }
    # no contract is built.
    it { assert_raises(NoMethodError) { NoContractOp.present({}).contract } }
    it { assert_raises(NoMethodError) { NoContractOp.run({}) } }
  end
end


class OperationTest < MiniTest::Spec
  # test #invalid!
  class OperationWithoutValidateCall < Trailblazer::Operation
    def process(params)
      params || invalid!(params)
    end

    include Inspect
  end

  # ::run
  it { OperationWithoutValidateCall.run(true).to_s.must_equal %{[true, <OperationWithoutValidateCall @model=>]} }
  # invalid.
  it { OperationWithoutValidateCall.run(false).to_s.must_equal %{[false, <OperationWithoutValidateCall @model=>]} }


  # #validate yields contract when valid
  class OperationWithValidateBlock < Trailblazer::Operation
    self.contract_class = class Contract
      def initialize(*)
      end

      def validate(params)
        params
      end
      self
    end

    def process(params)
      validate(params, Object.new) do |c|
        @secret_contract = c.class
      end
    end

    attr_reader :secret_contract
  end

  it { OperationWithValidateBlock.run(false).last.secret_contract.must_equal nil }
  it { OperationWithValidateBlock.(true).secret_contract.must_equal OperationWithValidateBlock::Contract }


  # test validate wit if/else
  class OperationWithValidateAndIf < Trailblazer::Operation
    self.contract_class = class Contract
      def initialize(*)
      end

      def validate(params)
        params
      end
      self
    end

    def process(params)
      if validate(params, Object.new)
        @secret_contract = contract.class
      else
        @secret_contract = "so wrong!"
      end
    end

    attr_reader :secret_contract
  end

  it { OperationWithValidateAndIf.run(false).last.secret_contract.must_equal "so wrong!" }
  it { OperationWithValidateAndIf.(true).secret_contract.must_equal OperationWithValidateAndIf::Contract }



  # ::present only runs #setup! which runs #model!.
  class ContractOnlyOperation < Trailblazer::Operation
    self.contract_class = class Contract
      def initialize(model)
        @_model = model
      end
      attr_reader :_model
      self
    end

    def model!(params)
      Object
    end

    def process(params)
      raise "This is not run!"
    end
  end

  it { ContractOnlyOperation.present({}).contract._model.must_equal Object }
end


class OperationErrorsTest < MiniTest::Spec
  class Operation < Trailblazer::Operation
    contract do
      property :title, validates: {presence: true}
    end

    def process(params)
      validate(params, OpenStruct.new) {}
    end
  end

  it do
    res, op = Operation.run({})
    op.errors.to_s.must_equal "{:title=>[\"can't be blank\"]}"
  end
end
