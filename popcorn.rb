#!/usr/bin/ruby

module Literals

   def Literals.parse(token)
      LOOKUP.each do |match, action|
         if token =~ match then
            return send(action, token)
         end
      end
   end

   def Literals.createFloat(token)
      return token.to_f
   end

   def Literals.createInteger(token)
      return token.to_i
   end

   def Literals.createString(token)
      # it is already a string, so all we have to do is remove the quotes
      return token[1..-2]
   end

   def Literals.createNull(token)
      return :PopNull
   end

   def Literals.createBool(token)
      return token == "true"
   end


   def Literals.createVariable(token)
      # strip the $ off the front of the variable
      # there is a number left, which is passed to PopVariable
      return PopVariable.new(Integer(token[1..-1]))
   end

   def Literals.createFunction(token)
      return PopFunctionCall.new(token)
   end


   class PopVariable
      attr_reader :number

      def initialize(number)
         @number = number
      end

      def to_s
         "#<PopVariable: $#{@number}>"
      end
   end

   class PopFunctionCall
      attr_reader :function_name

      def initialize(function_name)
         @function_name = function_name
      end

      def to_s
         "#<PopFunctioNCall: #{@function_name}>"
      end
   end

   # literals are looked up in this order.
   # the order is important to the regular expressions
   #  for example, if /^\d/ was seen before /^\d.*\./, then PC would think floats are integers.
   LOOKUP = [ [ /^-?\d*\.\d*$/ , :createFloat ] \
            , [ /^-?\d*$/      , :createInteger ] \
            , [ /^\"[^"]*\"/   , :createString ] \
            , [ /^null$/       , :createNull ] \
            , [ /^(true|false)$/ , :createBool ] \
            , [ /^\$\d+$/      , :createVariable ] \
            , [ /^.+$/         , :createFunction ] \
            ]

   DATA = [Float, Integer, Fixnum, String, :PopNull, true.class, false.class]

   def Literals.is_data? (item)
      DATA.include?(item.class)
   end

   def Literals.is_functioncall? (item)
      item.class == PopFunctionCall
   end
end

class PopFunction
   attr_reader :num_parameters

   def initialize(num_parameters, lambda_function)
      @num_parameters = num_parameters
      @code = lambda_function
   end

   def call(parameter_values)
      @code.call(*parameter_values)
   end
end

class PopUserFunction
   attr_reader :num_parameters

   def initialize(num_parameters, code_block)
      @num_parameters = num_parameters
      @code = code_block
      @Variables = num_parameters.times.map { |idx| Literals.PopVariable(idx) }
   end

   def call(parameter_values)
      code_instance = @code.dup

      parameter_values.zip(@Variables).each do |val, var|
         while idx = code_instance.find_index(var)
            code_instance[idx] = var
         end
      end

      code_instance
   end
end

class PopEmptyStack
   def initialize
   end
end

module Tests
   def Tests.run_all
      Tests.literals
      Tests.parse
   end

   def Tests.literals
      puts "Literals Test"
      puts Literals.parse("3.4").to_s
      puts Literals.parse("3").to_s
      puts Literals.parse("\"fart\"")
      puts Literals.parse("fartFunction")
      puts Literals.parse("$0")
   end

   def Tests.parse
      print Popcorn.parse_source("1 2 3 4 { 11 ass $1 41 } { \"LOLSTRING \t >:[{}{ }{}\" 1 2 { 3.0 4 } 5 6 { 7 8 { 9 10 } } } 1\n"), "\n"
      print Popcorn.parse_source("1 2 \t3\t4 { ass 21 31 41 } { 1 2 { \t3 4 } 5 6 { 7 8 { 9 10 } } } 1\n"), "\n"
   end
end

$functions = {}

module Builtins
   # the order of things given to the function are as follows:
   # ... $4 $3 $2 $1 $0 function
   # For example,
   #   30 20 -  is  30 - 20, with 30 being $1 and 20 being $0
   # Here, I use y, x to define the functions.
   # The order is important
   # lambda { |y, x| ... }
   #
   #  20 is passed in first to -
   #  then 30 is passed in to -
   # 

   # prints the top element of the stack
   $functions["println"] = PopFunction.new(1, lambda { |p| puts p })

   $functions["getln"] = PopFunction.new(0, lambda { STDIN.gets })

   # removes the top element of the stack without doing anything
   $functions["pop"] = PopFunction.new(1, lambda { |p| nil })
   
   # math
   $functions["+"] = PopFunction.new(2, lambda { |y,x| x + y })
   $functions["-"] = PopFunction.new(2, lambda { |y,x| x - y })
   $functions["*"] = PopFunction.new(2, lambda { |y,x| x * y })
   $functions["/"] = PopFunction.new(2, lambda { |y,x| x / y })

   # boolean
   $functions["and"] = PopFunction.new(2, lambda { |y,x| x and y })
   $functions["or"] = PopFunction.new(2, lambda { |y,x| x or y })
   $functions["not"] = PopFunction.new(1, lambda { |x| not x })
   
   # comparison
   $functions["=="] = PopFunction.new(2, lambda { |y,x| x == y })
   $functions["!="] = PopFunction.new(2, lambda { |y,x| x != y })
   $functions["<"] = PopFunction.new(2, lambda { |y,x| x < y })
   $functions["<="] = PopFunction.new(2, lambda { |y,x| x <= y })
   $functions[">"] = PopFunction.new(2, lambda { |y,x| x > y })
   $functions[">="] = PopFunction.new(2, lambda { |y,x| x >= y })

   # conversions
   $functions["to_i"] = PopFunction.new(1, lambda { |x| x.to_i })

   # ifelse
   # false-something true-something condition ifelse
   # returns the something that in the corresponding something
   $functions["ifelse"] = PopFunction.new(3, lambda { |b, t, f| b ? t : f })
      
   # define a function
   # {block} parameters name def
   $functions["def"] = PopFunction.new(2, lambda do |name, p, block|
         $functions[name] = PopUserFunction.new(p, block)
      end )

   # injects a block onto the stack
   # {block} exec

end

module Popcorn
   class PopcornInstance
      public
         def initialize(source_code)
            @namespace = {}

            @parse = Popcorn.parse_source(source_code)
         end

         def run
            @parse.each do |line|
               next if line.empty?

               run_block(line)
            end
         end

         def run_block(line)
            stream = line.reverse # this way pop pulls the first thing off
            stack = PopcornStack.new # the stack starts out empty

            while not stream.empty? do

               #puts "stream: #{stream}"
               #puts "stack: #{stack}\n\n"

               next_literal = stream.pop
   
               if Literals.is_data?(next_literal)
                  stack.push(next_literal)
               elsif Literals.is_functioncall?(next_literal)  # i.e., a function
                  function = $functions[next_literal.function_name]

                  #puts "function: #{function}"

                  param_values = stack.multipop(function.num_parameters)

                  result = function.call(param_values)
                  next if result == nil

                  result = [ result ] if result.class != Array

                  stream += result.reverse

               else
                  puts next_literal, next_literal.class
                  throw :NonFunctionOrDataPassedSomehow
               end

            end

         end
   end

   class PopcornStack
      def initialize
         @stack = []
      end

      def push(item)
         if item.is_a?(PopEmptyStack)
            throw :TryingToPushEmptyStack
         else
            @stack.push(item)
         end
      end

      def pop
         if @stack.length == 0
            return PopEmptyStack.new
         else
            @stack.pop
         end
      end

      def multipop(n)
         n.times.map { pop }
      end

      def to_s
         "<PopcornStack: #{@stack.to_s}>"
      end

   end

   def Popcorn.exec(source_code)
      pi = PopcornInstance.new(source_code)
      pi.run
   end

   def Popcorn.parse_source(raw_code)
      lines = []

      raw_code.split("\n").each do |line|
         line.strip!

         next if line.empty?

         # remove the comment and clean off any whitespace
         clean_line = line.split("#", 2)[0].strip

         next if clean_line.length == 0

         # pad the { } with spaces--this is a HACK so that people can do {1, 2}
         #if clean_line =~ /[{]/
         #   clean_line.gsub!(/(?=[\{\}])/, " ")
         #   clean_line.gsub!(/(?<=[\{\}])/, " ") 
         #end
         #  ... actually this doens't work because it pads {} in strings

         lines.push(parse_line(clean_line))
      end

      lines
   end

   def Popcorn.parse_line(raw_line)
      tokens = []
      while raw_line
         token, raw_line = Popcorn.next_token(raw_line)
         tokens.push(token) if token != nil
      end

      tokens
   end

   def Popcorn.next_token(raw_line)
      # clean off any whitespace in the front of the line
      raw_line.strip!

      if raw_line.length == 0
         return [nil, nil]
      end   


      # oh noes, a code block
      if raw_line[0] == '{' then      
         block = ""
         depth = 0
         bad = false
         exit_status = raw_line.each_char do |c|
            if c == '{'
               depth += 1
            elsif c == '}'
               depth -= 1
            end

            block += c

            if depth == 0
               break block
            end
         end

         # if at some point the thing broke, then good
         throw :MissingCloseBracket unless exit_status


         # parse the interior line without the brackets, then return it
         token = parse_line(block[1..-2].strip)
         rest = raw_line[block.length..-1]

      # oh noes, a frickin string (at least there is no depth)
      elsif raw_line[0] == '"'
         token, rest = raw_line[1..-1].split('"', 2)
         
         token = Literals.parse('"' + token + '"')

      else
         # otherwise we can just go until we find some whitespace
         token, rest = raw_line.split(/\s+/, 2)
         
         token = Literals.parse(token)
      end

      return [token, rest]
   end
end

#Tests.run_all

def main
   Popcorn.exec(File.new(ARGV[0]).read)
end


main
