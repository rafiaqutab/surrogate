require 'spec_helper'

describe 'singing' do
  describe 'in the block' do
    it 'sings to the class' do
      pristine_klass = Class.new do
        Mockingbird.song_for self do
          sing :find, default: 123
        end
      end

      klass1 = pristine_klass.reprise
      klass1.should_not have_been_told_to :find
      klass1.find(1).should == 123
      klass1.should have_been_told_to(:find).with(1)
    end
  end


  # are there parts of songs like "setup", "body", "conclusion"?
  # that would make it easier to talk about these, as the descriptions I'm using are obtuse

  describe 'out of the block' do
    let(:mocked_class) { Mockingbird.song_for Class.new }
    describe 'declaring the behaviour' do
      before     { mocked_class.sing :wink }
      let(:mock) { mocked_class.new }

      def self.shared_for_song_named_wink(name)
        it 'defines will_<song> which overrides the default' do
          mock1 = mocked_class.new
          mock2 = mocked_class.new
          mock1.will_wink :quickly
          mock2.will_wink :slowly
          mock1.wink.should == :quickly
          mock2.wink.should == :slowly
          mock1.wink.should == :quickly
        end
      end

      shared_for_song_named_wink("will_<song>") { |mock| mock.will_wink }
      # shared_setter("will_<song>") { |mock| mock.will_wink }

      context 'will_<song>_queue creates a queue of things to find then returns to normal behaviour' do
        specify 'when there is no default' do
          mock = mocked_class.new
          mock.will_wink_queue :quickly, :slowly
          mock.wink.should == :quickly
          mock.wink.should == :slowly
          expect { mock.wink }.to raise_error Mockingbird::UnpreparedMethodError
        end

        specify 'when there is a default' do
          mocked_class = Mockingbird.song_for(Class.new)
          mocked_class.sing :connect, default: :default
          mock = mocked_class.new
          mock.will_connect_queue 1, 2
          mock.connect.should == 1
          mock.connect.should == 2
          mock.connect.should == :default
        end

        specify 'when there is a default!' do
          mocked_class = Mockingbird.song_for(Class.new)
          mocked_class.sing :connect, default!: :default
          mock = mocked_class.new
          mock.will_connect_queue 1, 2
          mock.connect.should == 1
          mock.connect.should == 2
          mock.instance_variable_get(:@connect).should == :default
        end
      end
    end



    context 'the song' do
      it 'takes any number of arguments' do
        mocked_class.sing :meth, default: 1
        mocked_class.new.meth.should == 1
        mocked_class.new.meth(1).should == 1
        mocked_class.new.meth(1, 2).should == 1
      end

      it 'raises an UnpreparedMethodError when it has no default' do
        mocked_class.sing :meth
        expect { mocked_class.new.meth }.to raise_error(Mockingbird::UnpreparedMethodError, /meth/)
      end

      it 'considers ivars of the same name to be its default' do
        mocked_class.sing :meth
        mocked = mocked_class.new
        mocked.instance_variable_set :@meth, 123
        mocked.meth.should == 123
      end

      it 'reverts to the :default option if invoked and having no ivar' do
        mocked_class.sing :meth, default: 123
        mocked = mocked_class.new
        mocked.instance_variable_get(:@meth).should be_nil
        mocked.meth.should == 123
      end

      it 'sets the ivar to the :default! option if present' do
        mocked_class.sing :meth, default!: 123
        mocked = mocked_class.new
        mocked.instance_variable_get(:@meth).should == 123
      end

      describe 'initialization' do
        specify 'song can be an initialize method' do
          mocked_class.sing(:initialize) { @abc = 123 }
          mocked_class.new.instance_variable_get(:@abc).should == 123
        end

        specify 'initialize exsits even if error is raised' do
          mocked_class.sing(:initialize) { raise "simulate runtime error" }
          expect { mocked_class.new }.to raise_error(RuntimeError, /simulate/)
          expect { mocked_class.new }.to raise_error(RuntimeError, /simulate/)
        end

        specify 'receives args' do
          mocked_class.sing(:initialize) { |num1, num2| @num = num1 + num2 }
          mocked_class.new(25, 75).instance_variable_get(:@num).should == 100
        end

        specify 'default! variables are defined before initialize is called' do
          mocked_class.sing :abc, default!: 12
          mocked_class.sing(:initialize) { @abc *= 2 }
          mocked_class.new.abc.should == 24
        end

        specify 'even works with inheritance' do
          superclass = Class.new
          superclass.send(:define_method, :initialize) { @a = 1 }
          subclass = Class.new superclass
          mocked_subclass = Mockingbird.song_for Class.new subclass
          mocked_subclass.sing :abc
          mocked_subclass.new.instance_variable_get(:@a).should == 1
        end

        context 'when not a song' do
          it 'respects arity (this is probably 1.9.3 only)' do
            expect { mocked_class.new(1) }.to raise_error ArgumentError, 'wrong number of arguments(1 for 0)'
          end

          specify 'recorded regardless of when initialize is defined in relation to mock' do
            klass = Class.new do
              Mockingbird.song_for self
              def initialize(a)
                @a = a
              end
            end
            klass.new(1).should have_been_initialized_with 1
            klass.new(1).instance_variable_get(:@a).should == 1

            klass = Class.new do
              def initialize(a)
                @a = a
              end
              Mockingbird.song_for self
            end
            klass.new(1).should have_been_initialized_with 1
            klass.new(1).instance_variable_get(:@a).should == 1
          end
        end
      end

      describe 'it takes a block whos return value will be used as the default' do
        specify 'the block is instance evaled' do
          mocked_class.sing(:meth) { self }
          instance = mocked_class.new
          instance.meth.should equal instance
        end

        specify 'arguments passed to the method will be passed to the block' do
          mocked_class.sing(:meth) { |*args| args }
          instance = mocked_class.new
          instance.meth(1).should == [1]
          instance.meth(1, 2).should == [1, 2]
        end
      end

      it 'remembers what it was invoked with' do
        mocked_class.sing :meth, default: 123
        mock = mocked_class.new
        mock.meth 1
        mock.meth 1, 2
        mock.meth [1, 2]
        mock.invocations(:meth).should == [
          [1],
          [1, 2],
          [[1, 2]],
        ]
      end

      it 'raises an error if asked about invocations for songs it does not know' do
        mocked_class.sing :meth1
        mocked_class.sing :meth2
        mock = mocked_class.new
        expect { mock.invocations(:meth1) }.to_not raise_error
        expect { mock.invocations(:meth3) }.to raise_error Mockingbird::UnknownSong, /doesn't know "meth3", only knows "initialize", "meth1", "meth2"/
      end
    end
  end


  describe 'reprise' do
    it 'a repetition or further performance of the klass' do
      pristine_klass = Class.new do
        Mockingbird.song_for self do
          sing :find, default: 123
          sing(:bind) { 'abc' }
        end
        sing :peat, default: true
        sing(:repeat) { 321 }
      end

      klass1 = pristine_klass.reprise
      klass1.should_not have_been_told_to :find
      klass1.find(1).should == 123
      klass1.should have_been_told_to(:find).with(1)
      klass1.bind.should == 'abc'

      klass2 = pristine_klass.reprise
      klass2.will_find 456
      klass2.find(2).should == 456
      klass1.find.should == 123

      klass1.should have_been_told_to(:find).with(1)
      klass2.should have_been_told_to(:find).with(2)
      klass1.should_not have_been_told_to(:find).with(2)
      klass2.should_not have_been_told_to(:find).with(1)

      klass1.new.peat.should == true
      klass1.new.repeat.should == 321
    end

    it 'is a subclass of the reprised class' do
      superclass = Mockingbird.song_for Class.new
      superclass.reprise.new.should be_a_kind_of superclass
    end
  end
end