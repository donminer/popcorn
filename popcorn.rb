#!/usr/bin/ruby

class Macro
   attr_reader :name, :params

   def initialize(def_string, parent)
      @parent = parent
      tokens = def_string.split(/\s+/)
      @name = tokens[1]
      @params = tokens[2].to_i
      idx = 3
      while(tokens[idx] != ':')
         @params.push tokens[idx]
         idx += 1
      end
      idx += 1

      @code = []
      while(tokens[idx] != ':')
         @code.push tokens[idx]
         idx += 1
      end
      @code.reverse!
      idx += 1
      
      #skip over if
      idx += 1

      @condition = tokens[idx..-1]

   end

   def expand(parameters)
      if not check_conditions(parameters)
         return []
      end

      @code.map do |token|
         if token =~ /^\$/
            parameters[ token[1..-1].to_i ].to_s
         else
            token.to_s
         end
      end
   end

   def check_conditions(parameters)
      injected = @condition.map do |token|
         if token =~ /^\$/
            parameters[ token[1..-1].to_i ]
         else
            token
         end
      end


      @parent.eval_line(injected.join(' '))[0] == 'T'
   end
end

class Popcorn

   attr_reader :stack, :macros

   def initialize(file_name)
      @macros = {}

      File.open(file_name) do |infile|
         while (line = infile.gets)
            if line =~ /^macro\s/
               m = Macro.new(line, self)
               @macros[m.name] = m
               #print "defined macro #{m.name}!\n"
            else
               eval_line(line)
            end
         end
      end


   end

   def eval_line(line)
      # tokenize on whitespace, then reverse it (so it looks like a stack)
      tokens = line.split(/\s/).reverse!

      stack = []
   
      while(tokens.length > 0)
         #print "##line: #{line.chomp}\n"
         #print "tokens: #{tokens}\n"
         #print " stack: #{stack}\n\n"

         token = tokens.pop
   
         case token
            when "+" then stack[-2, 2] = stack[-1] + stack[-2]
            when "-" then stack[-2, 2] = stack[-2] - stack[-1]
            when "*" then stack[-2, 2] = stack[-1] * stack[-2]
            when "/" then stack[-2, 2] = stack[-2] / stack[-1]
            when "=" then stack[-2, 2] = (stack[-2] == stack[-1]).to_s[0].upcase
            when "!=" then stack[-2, 2] = (stack[-2] != stack[-1]).to_s[0].upcase
            when "<" then stack[-2, 2] = (stack[-2] < stack[-1]).to_s[0].upcase
            when ">" then stack[-2, 2] = (stack[-2] > stack[-1]).to_s[0].upcase
            when "<=" then stack[-2, 2] = (stack[-2] <= stack[-1]).to_s[0].upcase
            when ">=" then stack[-2, 2] = (stack[-2] >= stack[-1]).to_s[0].upcase
            when "T" then stack.push("T")
            when "F" then stack.push("F")
            when "print" then print "#{stack.pop}\n"

            when /^\d/ then stack.push(token.to_f)
            when /^%/ then
               m = @macros[ token[1..-1] ]
               params = []
               m.params.times { params.push(stack.pop) }
               tokens += m.expand(params)



         end
      end

      return stack
   end

end

Popcorn.new('test.pc')

