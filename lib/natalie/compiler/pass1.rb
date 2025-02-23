require_relative './base_pass'
require_relative './method_args'
require_relative './multiple_assignment'
require_relative '../../../build/generated/numbers'

module Natalie
  class Compiler
    # Process S-expressions from the Ruby parser.
    class Pass1 < BasePass
      MAX_FIXNUM = NAT_MAX_FIXNUM
      MIN_FIXNUM = NAT_MIN_FIXNUM

      def initialize(compiler_context)
        super
        self.default_method = nil
        self.warn_on_default = true
        self.require_empty = false
        self.strict = false
        @retry_context = []
      end

      def go(ast)
        process(ast)
      end

      def process_alias(exp)
        _, new_name, old_name = exp
        exp.new(:block, s(:alias, :self, :env, process(new_name), process(old_name)), s(:nil))
      end

      def process_undef(exp)
        _, (_, name) = exp
        exp.new(:block, s(:undefine_method, :self, :env, s(:intern, name)), s(:nil))
      end

      def process_and(exp)
        _, lhs, rhs = exp
        rhs = process(rhs)
        lhs_result = temp('lhs')
        exp.new(:block, s(:declare, lhs_result, process(lhs)), s(:c_if, s(:is_truthy, lhs_result), rhs, lhs_result))
      end

      def process_array(exp)
        _, *items = exp
        arr = temp('arr')

        if !items.any? { |item| item.sexp_type == :splat }
          return exp.new(:block, s(:declare, arr, s(:new, :ArrayObject, *items.map { |a| process(a) })), arr)
        else
          items =
            items.map do |item|
              if item.sexp_type == :splat
                s(:push_splat, s(:l, "#{arr}->as_array()"), :env, process(item.last))
              else
                s(:push, s(:l, "#{arr}->as_array()"), process(item))
              end
            end
          return exp.new(:block, s(:declare, arr, s(:new, :ArrayObject)), *items.compact, arr)
        end
      end

      def process_attrasgn(exp)
        _, receiver, message, *args = exp
        if args.any? { |a| a.sexp_type == :splat }
          args = s(:args_array, process(s(:array, *args.map { |n| process(n) })))
        else
          args = s(:args, *args.map { |n| process(n) })
        end
        exp.new(:public_send, process(receiver), s(:intern, message), args)
      end

      def process_back_ref(exp)
        _, name = exp
        raise "Unknown back ref: #{name.inspect}" unless name == :&
        match = temp('match')
        exp.new(
          :block,
          s(:declare, match, s(:last_match, :env)),
          s(:c_if, s(:is_truthy, match), s(:public_send, match, s(:intern, :to_s)), s(:nil)),
        )
      end

      # bare begin without rescue
      def process_begin(exp)
        _, code_block = exp
        process(code_block)
      end

      def process_block(exp)
        _, *parts = exp
        exp.new(:block, *parts.map { |p| p.is_a?(Sexp) ? process(p) : p })
      end

      VALID_BREAK_CONTEXT = %i[iter while until]
      BREAK_LOOPS = %i[while until]

      def process_break(exp)
        _, value = exp
        value ||= s(:nil)
        exp.new(:break, process(value))
      end

      def process_call(exp, is_super: false)
        _, receiver, method, *args = exp
        if @compiler_context[:inline_cpp_enabled]
          if %i[__inline__ __define_method__ __cxx_flags__ __ld_flags__ __function__ __constant__].include?(method)
            return exp.new(method, *args)
          end
          return exp.new(method, args.first, *args[1..-1].map { |a| process(a) }) if method == :__call__
        end
        _, block_pass = args.pop if args.last&.sexp_type == :block_pass
        if args.any? { |a| a.sexp_type == :splat }
          args = s(:args_array, process(s(:array, *args.map { |n| process(n) })))
        else
          args = s(:args, *args.map { |a| process(a) })
        end
        receiver = receiver ? process(receiver) : :self
        return exp.new(:send, receiver, s(:intern, method), args, 'block') if method == :block_given?
        call =
          if is_super == :zsuper
            exp.new(:super, nil)
          elsif is_super
            exp.new(:super, args)
          elsif receiver == :self
            exp.new(:send, receiver, s(:intern, method), args)
          else
            exp.new(:public_send, receiver, s(:intern, method), args)
          end
        if block_pass
          proc_name = temp('proc_to_block')
          call << "proc_to_block_arg(env, #{proc_name})"
          exp.new(:block, s(:declare, proc_name, process(block_pass)), call)
        else
          call << 'nullptr'
          call
        end
      end

      def process_case(exp)
        _, value, *whens, else_body = exp
        if value
          # matching against a value
          value_name = temp('case_value')
          cond = s(:cond)
          whens.each do |when_exp|
            raise "TODO: pattern matching with case/in" if when_exp.sexp_type == :in
            _, (_, *matchers), *when_body = when_exp
            when_body = when_body.map { |w| process(w) }
            when_body = [s(:nil)] if when_body == [nil]
            full_condition =
              s(
                :is_truthy,
                # FIXME: Get rid of the :nil here
                # FIXME: This is still a bit hacky
                matchers.reduce(s(:nil)) do |new_cond, matcher|
                  if matcher.sexp_type == :splat
                    _, matcher = matcher
                    is_splat = 'true'
                  else
                    is_splat = 'false'
                  end
                  process_or(s(:or, new_cond, s(:is_case_equal, :env, value_name, process(matcher), is_splat)))
                end,
              )
            cond << full_condition
            cond << s(:block, *when_body)
          end
          cond << s(:else)
          cond << process(else_body || s(:nil))
          exp.new(:block, s(:declare, value_name, process(value)), cond)
        else
          # just a glorified if/elsif
          cond = exp.new(:cond)
          whens.each do |when_exp|
            _, (_, *matchers), *when_body = when_exp
            when_body = when_body.map { |w| process(w) }
            when_body = [s(:nil)] if when_body == [nil]
            matchers.each do |matcher|
              cond << s(:is_truthy, process(matcher))
              cond << s(:block, *when_body)
            end
          end
          cond << s(:else)
          cond << process(else_body || s(:nil))
          cond
        end
      end

      def process_cdecl(exp)
        _, name, value = exp
        namespace, name = constant_name(name)
        exp.new(:const_set, namespace, s(:intern, name), process(value))
      end

      def process_class(exp)
        _, name, superclass, *body = exp
        namespace, name = constant_name(name)
        superclass ||= s(:const, 'Object')
        fn = temp('class_body')
        ns = temp('class_namespace')
        klass = temp('class')
        exp.new(
          :block,
          s(:class_fn, fn, process(s(:block, *body))),
          s(:declare, ns, namespace),
          s(:declare, klass, s(:const_get, ns, s(:intern, name))),
          s(
            :c_if,
            s(:c_not, klass),
            s(
              :block,
              s(:set, klass, s(:subclass, process(superclass), :env, s(:s, name))),
              s(:const_set, ns, s(:intern, name), klass),
            ),
          ),
          s(:eval_body, s(:l, "#{klass}->as_class()"), :env, fn),
        )
      end

      def constant_name(name)
        if name.is_a?(Symbol)
          namespace = :self
        elsif name.sexp_type == :colon2
          _, namespace, name = name
          namespace = process(namespace)
        elsif name.sexp_type == :colon3
          _, name = name
          namespace = s(:l, 'GlobalEnv::the()->Object()')
        else
          raise "Unknown constant name type #{name.sexp_type.inspect}"
        end
        [namespace, name]
      end

      def process_colon2(exp)
        _, parent, name = exp
        parent_name = temp('parent')
        exp.new(:block, s(:declare, parent_name, process(parent)), s(:const_find, parent_name, :env, s(:intern, name)))
      end

      def process_colon3(exp)
        _, name = exp
        exp.new(:const_find, s(:l, 'GlobalEnv::the()->Object()'), :env, s(:intern, name))
      end

      def process_const(exp)
        _, name = exp
        exp.new(:const_find, :self, :env, s(:intern, name), 'Object::ConstLookupSearchMode::NotStrict')
      end

      def process_cvdecl(exp)
        _, name, value = exp
        exp.new(:cvar_set, :self, :env, s(:intern, name), process(value))
      end

      def process_cvasgn(exp)
        _, name, value = exp
        exp.new(:cvar_set, :self, :env, s(:intern, name), process(value))
      end

      def process_cvar(exp)
        _, name = exp
        exp.new(:cvar_get, :self, :env, s(:intern, name))
      end

      def process_defined(exp)
        _, name = exp
        name = process(name) if name.sexp_type == :call
        exp.new(:defined, name)
      end

      def process_defn_internal(exp)
        _, name, (_, *args), *body = exp
        name = name.to_s
        fn_name = temp("def_#{name}_")
        if args.last&.to_s&.start_with?('&')
          arg_name = args.pop.to_s[1..-1]
          block_arg = exp.new(:var_set, :env, s(:s, arg_name), s(:'ProcObject::from_block_maybe', 'block'))
        end
        if args.any?
          args_name = temp('args_as_vector')
          method_args = MethodArgs.new(args, args_name)
          assign_args =
            s(
              :block,
              s(:declare, args_name, exp.new(:'TM::Vector<Value>', s(:l, 'args.size()')), :'auto&'),
              s(:args_to_vector, args_name, :args),
              process(method_args.set_args),
            )
          arity = method_args.arity
        else
          assign_args = s(:block)
          arity = 0
        end
        method_body = process(s(:block, *body))
        fn =
          exp.new(
            :def_fn,
            fn_name,
            s(:block, prepare_argc_assertion(args), assign_args, block_arg || s(:block), method_body),
          )
        [fn, arity]
      end

      def process_defn(exp)
        _, name, * = exp
        fn, arity = process_defn_internal(exp)
        exp.new(:block, fn, s(:define_method, :self, :env, s(:intern, name), fn[1], arity))
      end

      def process_defs(exp)
        _, owner, name, args, *body = exp
        fn, arity = process_defn_internal(exp.new(:defs, name, args, *body))
        exp.new(:block, fn, s(:define_singleton_method, process(owner), :env, s(:intern, name), fn[1], arity))
      end

      def process_dot2(exp)
        _, beginning, ending = exp
        beginning = s(:nil) if beginning.nil?
        ending = s(:nil) if ending.nil?
        exp.new(:new, :RangeObject, process(beginning), process(ending), 0)
      end

      def process_dot3(exp)
        _, beginning, ending = exp
        beginning = s(:nil) if beginning.nil?
        ending = s(:nil) if ending.nil?
        exp.new(:new, :RangeObject, process(beginning), process(ending), 1)
      end

      def process_dregx(exp)
        str_node = process_dstr(exp)
        str = str_node.pop
        str_node << exp.new(:new, :RegexpObject, :env, s(:l, "#{str}->as_string()->c_str()"))
        str_node
      end

      # TODO: support /o option on Regexes which compiles the literal only once
      alias process_dregx_once process_dregx

      def process_dstr(exp)
        _, start, *rest = exp
        string = temp('string')
        segments =
          rest.map do |segment|
            case segment.sexp_type
            when :evstr
              s(:append, s(:as_string, string), :env, process(s(:call, segment.last, :to_s)))
            when :str
              s(:append, s(:as_string, string), :env, s(:s, segment.last))
            else
              raise "unknown dstr segment: #{segment.inspect}"
            end
          end
        exp.new(:block, s(:declare, string, s(:new, :StringObject, s(:s, start))), *segments, string)
      end

      def process_dxstr(exp)
        exp.new(:shell_backticks, :env, process_dstr(exp))
      end

      def process_xstr(exp)
        exp.new(:shell_backticks, :env, process_str(exp))
      end

      def process_dsym(exp)
        str_node = process_dstr(exp)
        str = str_node.pop
        str_node << exp.new(:l, "Value { #{str}->as_string()->to_symbol(env) }")
        str_node
      end

      def process_ensure(exp)
        _, body, ensure_body = exp
        process(
          exp.new(
            :block,
            s(:rescue, body, s(:resbody, s(:array), ensure_body, s(:raise_exception, :env, :exception))),
            ensure_body,
          ),
        )
      end

      def process_gasgn(exp)
        _, name, value = exp
        exp.new(:global_set, :env, s(:intern, name), process(value))
      end

      def process_gvar(exp)
        _, name = exp
        case name
        when :$~
          exp.new(:last_match, :env)
        when :$!
          exp.new(:exception_object, :env)
        else
          exp.new(:global_get, :env, s(:intern, name))
        end
      end

      def process_hash(exp)
        _, *pairs = exp
        hash = temp('hash')
        inserts =
          pairs
            .each_slice(2)
            .map { |(key, val)| s(:put, s(:l, "#{hash}->as_hash()"), :env, process(key), process(val)) }
        exp.new(:block, s(:declare, hash, s(:new, :HashObject)), s(:block, *inserts), hash)
      end
      alias process_bare_hash process_hash # TODO: handle this separately for keyword args

      def process_if(exp)
        _, condition, true_body, false_body = exp
        condition = exp.new(:is_truthy, process(condition))
        exp.new(:c_if, condition, process(true_body || s(:nil)), process(false_body || s(:nil)))
      end

      def process_iasgn(exp)
        _, name, value = exp
        exp.new(:ivar_set, :self, :env, s(:intern, name), process(value))
      end

      def process_iter(exp)
        _, call, (_, *args), *body = exp
        return exp if call.sexp_type == :block_fn # already processed

        is_lambda = is_lambda_call?(call)
        is_proc = !is_lambda

        args = fix_unnecessary_nesting(args)
        if args.last&.to_s&.start_with?('&')
          arg_name = args.pop.to_s[1..-1]
          block_arg = exp.new(:arg_set, :env, s(:s, arg_name), s(:'ProcObject::from_block_maybe', 'block'))
        end
        block_fn = temp('block_fn')
        block = block_fn.sub(/_fn/, '')

        call = process(call)
        if (i = call.index('nullptr'))
          call[i] = block
        else
          puts "#{exp.file}##{exp.line}"
          pp call
          raise 'cannot add block to call!'
        end
        if args.any?
          args_name = temp('args_as_vector')
          method_args = MethodArgs.new(args, args_name, is_proc: is_proc)
          assign_args =
            s(
              :block,
              s(:declare, args_name, exp.new(:'TM::Vector<Value>'), :'auto&'),
              s(:block_args_to_vector, :env, args_name, args.size, :args),
              process(method_args.set_args),
            )
          arity = method_args.arity
        else
          assign_args = s(:block)
          arity = 0
        end
        argc_assertion = prepare_argc_assertion(args) if is_lambda
        exp.new(
          :iter,
          s(
            :block_fn,
            block_fn,
            s(:block, argc_assertion || s(:block), assign_args, block_arg || s(:block), process(s(:block, *body))),
          ),
          s(:declare_block, block, s(:new, :Block, :env, :self, block_fn, arity)),
          call,
        )
      end

      def is_lambda_call?(exp)
        exp == s(:lambda) || exp == s(:call, nil, :lambda)
      end

      # |(a, b)| should be treated as |a, b|
      def fix_unnecessary_nesting(args)
        args.size == 1 && args.first.is_a?(Sexp) && args.first.sexp_type == :masgn ? args.first[1..-1] : args
      end

      def process_ivar(exp)
        _, name = exp
        exp.new(:ivar_get, :self, :env, s(:intern, name))
      end

      def process_lambda(exp)
        # note: the nullptr gets overwritten with an actual block by process_iter later
        exp.new(:new, :ProcObject, 'nullptr', :'ProcObject::ProcType::Lambda')
      end

      def process_lasgn(exp)
        _, name, val = exp
        return exp.new(:var_declare, :env, s(:s, name)) if val == s(:lvar, name)
        exp.new(:var_set, :env, s(:s, name), process(val))
      end

      def process_lit(exp)
        lit = exp.last
        case lit
        when Float
          exp.new(:'Value::floatingpoint', lit)
        when Integer
          if lit > MAX_FIXNUM || lit < MIN_FIXNUM
            str = lit.to_s
            exp.new(:'IntegerObject::create', s(:s, str))
          else
            exp.new(:'Value::integer', lit)
          end
        when Range
          exp.new(
            :new,
            :RangeObject,
            process_lit(s(:lit, lit.first)),
            process_lit(s(:lit, lit.last)),
            lit.exclude_end? ? 1 : 0,
          )
        when Regexp
          exp.new(:'RegexpObject::literal', :env, s(:s, lit.source), lit.options)
        when Symbol
          exp.new(:intern_value, lit)
        else
          raise "unknown lit: #{exp.inspect} (#{exp.file}\##{exp.line})"
        end
      end

      def process_lvar(exp)
        _, name = exp
        exp.new(:var_get, :env, s(:s, name))
      end

      def process_masgn(exp)
        value_name = temp('masgn_value')
        process(MultipleAssignment.new(exp, value_name).generate)
      end

      def prepare_argc_assertion(args)
        min = 0
        max = 0
        has_kwargs = false
        args.each do |arg|
          if arg.is_a?(Symbol)
            if arg.start_with?('*')
              max = :unlimited
            else
              min += 1
              max += 1 if max != :unlimited
            end
          elsif arg.sexp_type == :kwarg
            max += 1 unless has_kwargs || max == :unlimited # FIXME: incrementing max here is wrong; it produces the wrong error message
            has_kwargs = true
          else
            max += 1 if max != :unlimited
          end
        end
        if max == :unlimited
          min.zero? ? s(:block) : s(:ensure_argc_at_least, :args, :env, min)
        elsif min == max
          s(:ensure_argc_is, :args, :env, min)
        else
          s(:ensure_argc_between, :args, :env, min, max)
        end
      end

      def process_match2(exp)
        _, regexp, string = exp
        exp.new(:public_send, process(regexp), s(:intern, '=~'), s(:args, process(string)))
      end

      def process_match3(exp)
        _, string, regexp = exp
        exp.new(:public_send, process(regexp), s(:intern, '=~'), s(:args, process(string)))
      end

      def process_module(exp)
        _, name, *body = exp
        namespace, name = constant_name(name)
        fn = temp('module_body')
        ns = temp('module_namespace')
        mod = temp('module')
        exp.new(
          :block,
          s(:module_fn, fn, process(s(:block, *body))),
          s(:declare, ns, namespace),
          s(:declare, mod, s(:const_get, ns, s(:intern, name))),
          s(
            :c_if,
            s(:c_not, mod),
            s(:block, s(:set, mod, s(:new, :ModuleObject, s(:s, name))), s(:const_set, ns, s(:intern, name), mod)),
          ),
          exp.new(:eval_body, s(:l, "#{mod}->as_module()"), :env, fn),
        )
      end

      def process_next(exp)
        _, value = exp
        value ||= s(:nil)
        exp.new(:c_return, process(value))
      end

      def process_nth_ref(exp)
        _, num = exp
        match = temp('match')
        exp.new(
          :block,
          s(:declare, match, s(:last_match, :env)),
          s(
            :c_if,
            s(:is_truthy, match),
            s(:public_send, match, s(:intern, :[]), s(:args, s(:new, :IntegerObject, num))),
            s(:nil),
          ),
        )
      end

      def process_not(exp)
        _, value = exp
        exp.new(:public_send, process(value), s(:intern, :!), s(:args))
      end

      def process_op_asgn1(exp)
        _, obj, (_, *key_args), op, *val_args = exp
        val = temp('val')
        obj_name = temp('obj')
        if op == :'||'
          exp.new(
            :block,
            s(:declare, obj_name, process(obj)),
            s(
              :declare,
              val,
              s(:public_send, obj_name, s(:intern, :[]), s(:args, *key_args.map { |a| process(a) }), 'nullptr'),
            ),
            s(
              :c_if,
              s(:is_truthy, val),
              val,
              s(
                :public_send,
                obj_name,
                s(:intern, :[]=),
                s(:args, *key_args.map { |a| process(a) }, *val_args.map { |a| process(a) }),
                'nullptr',
              ),
            ),
          )
        else
          # math operators
          exp.new(
            :block,
            s(:declare, obj_name, process(obj)),
            s(
              :declare,
              val,
              s(
                :public_send,
                s(:public_send, obj_name, s(:intern, :[]), s(:args, *key_args.map { |a| process(a) }), 'nullptr'),
                s(:intern, op),
                s(:args, *val_args.map { |a| process(a) }),
                'nullptr',
              ),
            ),
            s(:public_send, obj_name, s(:intern, :[]=), s(:args, *key_args.map { |a| process(a) }, val), 'nullptr'),
          )
        end
      end

      def process_op_asgn2(exp)
        _, obj, writer, op, *val_args = exp
        raise 'expected writer=' unless writer =~ /=$/
        reader = writer.to_s.chop
        val = temp('val')
        obj_name = temp('obj')
        if op == :'||'
          exp.new(
            :block,
            s(:declare, obj_name, process(obj)),
            s(:declare, val, s(:public_send, obj_name, s(:intern, reader), s(:args))),
            s(
              :c_if,
              s(:is_truthy, val),
              val,
              s(:public_send, obj_name, s(:intern, writer), s(:args, *val_args.map { |a| process(a) })),
            ),
          )
        else
          exp.new(
            :block,
            s(:declare, obj_name, process(obj)),
            s(
              :declare,
              val,
              s(
                :public_send,
                s(:public_send, obj_name, s(:intern, reader), s(:args)),
                s(:intern, op),
                s(:args, *val_args.map { |a| process(a) }),
              ),
            ),
            s(:public_send, obj_name, s(:intern, writer), s(:args, val)),
          )
        end
      end

      def process_op_asgn_and(exp)
        process_op_asgn_bool(exp, condition: ->(result_name) { s(:c_not, s(:is_truthy, result_name)) })
      end

      def process_op_asgn_or(exp)
        process_op_asgn_bool(exp, condition: ->(result_name) { s(:is_truthy, result_name) })
      end

      def process_op_asgn_bool(exp, condition:)
        _, (var_type, name), value = exp
        case var_type
        when :cvar
          result_name = temp('cvar')
          exp.new(
            :block,
            s(:declare, result_name, s(:cvar_get_or_null, :self, :env, s(:intern, name))),
            s(:c_if, s(:and, s(:l, result_name), condition.(result_name)), result_name, process(value)),
          )
        when :gvar
          result_name = temp('gvar')
          exp.new(
            :block,
            s(:declare, result_name, s(:global_get, :env, s(:intern, name))),
            s(:c_if, condition.(result_name), result_name, process(value)),
          )
        when :ivar
          result_name = temp('ivar')
          exp.new(
            :block,
            s(:declare, result_name, s(:ivar_get, :self, :env, s(:intern, name))),
            s(:c_if, condition.(result_name), result_name, process(value)),
          )
        when :lvar
          var = process(s(:lvar, name))
          exp.new(
            :block,
            s(:var_declare, :env, s(:s, name)),
            s(:c_if, s(:defined, s(:lvar, name)), s(:c_if, condition.(var), var, process(value))),
          )
        when :call
          _, call, attrasgn = exp
          result_name = temp('op_asgn_bool')
          exp.new(
            :block,
            s(:declare, result_name, process(call)),
            s(:c_if, condition.(result_name), result_name, process(attrasgn)),
          )
        else
          p exp
          p exp.file
          p exp.line
          raise "unknown op_asgn_or type: #{var_type.inspect}"
        end
      end

      def process_or(exp)
        _, lhs, rhs = exp
        rhs = process(rhs)
        lhs_result = temp('lhs')
        exp.new(
          :block,
          s(:declare, lhs_result, process(lhs)),
          s(:c_if, s(:c_not, s(:is_truthy, lhs_result)), rhs, lhs_result),
        )
      end

      def process_rescue(exp)
        _, *rest = exp
        retry_name = temp('should_retry')
        retry_context(retry_name) do
          else_body = rest.pop if rest.last.sexp_type != :resbody
          body, resbodies = rest.partition { |n| n.first != :resbody }
          rescue_cond = s(:cond)

          resbodies.each_with_index do |(_, (_, *match), *resbody), index|
            lasgn = match.pop if match.last&.sexp_type == :lasgn
            match << s(:const, 'StandardError') if match.empty?
            condition = s(:is_a, :exception, *match.map { |n| process(n) })
            rescue_cond << condition
            resbody = resbody == [nil] ? [s(:nil)] : resbody.map { |n| process(n) }
            rescue_cond << (lasgn ? s(:block, process(lasgn), *resbody) : s(:block, *resbody))
          end
          rescue_cond << s(:else)
          rescue_cond << s(:block, s(:raise_exception, :env, :exception))
          body << else_body if else_body
          body = body.empty? ? [s(:nil)] : body

          result_name = temp('rescue_result')

          exp.new(
            :block,
            s(:declare, retry_name, :false, :bool),
            s(
              :rescue_do,
              s(:block, s(:set, retry_name, :false), s(:rescue, s(:block, *body.map { |n| process(n) }), rescue_cond)),
              retry_name,
              result_name,
            ),
          )
        end
      end

      def process_redo(exp)
        redo_name = temp('redo')
        exp.new(:block, s(:declare, redo_name, s(:nil)), s(:add_redo_flag, redo_name), s(:c_return, redo_name))
      end

      def process_retry(exp)
        retry_name = @retry_context.last
        raise 'No proper rescue context!' if retry_name.nil?
        exp.new(:block, s(:set, retry_name, :true), s(:c_continue))
      end

      RETURN_CONTEXT = %i[defn defs iter]

      def process_return(exp)
        _, value = exp
        exp.new(:return, process(value))
      end

      def process_safe_call(exp)
        _, receiver, method, *args = exp
        obj = temp('safe_call_obj')
        exp.new(
          :block,
          s(:declare, obj, process(receiver)),
          s(:c_if, s(:is_truthy, obj), process(exp.new(:call, receiver, method, *args)), s(:nil)),
        )
      end

      def process_sclass(exp)
        _, obj, *body = exp
        fn = temp('singleton_class_body')
        klass = temp('singleton_class')
        exp.new(
          :block,
          s(:class_fn, fn, process(s(:block, *body))),
          s(:declare, klass, s(:singleton_class, process(obj), :env)),
          s(:eval_body, s(:l, "#{klass}->as_class()"), :env, fn),
        )
      end

      def process_str(exp)
        _, str = exp
        if str.empty?
          exp.new(:new, :StringObject)
        else
          exp.new(:new, :StringObject, s(:s, str), str.bytes.size)
        end
      end

      def process_struct(exp)
        _, hash = exp
        exp.new(:struct, process_atom(hash))
      end

      def process_super(exp)
        _, *args = exp
        process_call(exp.new(:call, nil, :super, *args), is_super: true)
      end

      def process_svalue(exp)
        _, svalue = exp
        case svalue.sexp_type
        when :splat
          _, value = svalue
          exp.new(:splat, :env, process(value))
        when :array
          process_array(svalue)
        else
          raise "Unknown svalue type #{svalue.sexp_type.inspect}"
        end
      end

      def process_until(exp)
        _, condition, body, pre = exp
        process_while(exp.new(:while, s(:not, condition), body, pre))
      end

      def process_while(exp)
        _, condition, body, pre = exp
        body ||= s(:nil)
        result_name = temp('while_result')
        cond = s(:c_if, s(:c_not, s(:is_truthy, process(condition))), s(:c_break))
        loop_body = pre ? s(:block, cond, process(body)) : s(:block, process(body), cond)
        exp.new(
          :block,
          s(:declare, result_name, s(:nil)),
          s(:loop, result_name, s(:block, loop_body, s(:NAT_HANDLE_BREAK, result_name, :break))),
          result_name,
        )
      end

      def process_yield(exp)
        _, *args = exp
        if args.any? { |a| a.sexp_type == :splat }
          args = s(:args_array, process(s(:array, *args.map { |n| process(n) })))
        else
          args = s(:args, *args.map { |n| process(n) })
        end
        exp.new(:NAT_RUN_BLOCK_FROM_ENV, args)
      end

      def process_zsuper(exp)
        process_call(exp.new(:call, nil, :super), is_super: :zsuper)
      end

      def temp(name)
        n = @compiler_context[:var_num] += 1
        "#{@compiler_context[:var_prefix]}#{name.gsub(/[^a-z0-9_]/i, '_')}#{n}"
      end

      def retry_context(name)
        @retry_context << name
        exp = yield
        @retry_context.pop
        exp
      end
    end
  end
end
