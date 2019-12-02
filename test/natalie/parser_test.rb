require 'minitest/spec'
require 'minitest/autorun'

describe 'Natalie::Parser' do
  def build_ast(code)
    # Don't hard-depend on the internal implementation, but use it most of the time for speed.
    if rand(50) == 0
      out = `#{bin} --ast -e #{code.inspect} 2>&1`
      raise out if out =~ /lib\/natalie.*Error/
      eval(out)
    else
      require_relative '../../lib/natalie/parser'
      Natalie::Parser.new(code).ast
    end
  end

  def bin
    File.expand_path('../../bin/natalie', __dir__)
  end

  describe 'AST' do
    it 'parses integers' do
      ast = build_ast('1')
      ast.must_equal [[:integer, '1']]
      ast = build_ast('-3')
      ast.must_equal [[:integer, '-3']]
      ast = build_ast('2 - 3')
      ast.must_equal [[:send, [:integer, '2'], '-', [[:integer, '3']]]]
      ast = build_ast('2-3')
      ast.must_equal [[:send, [:integer, '2'], '-', [[:integer, '3']]]]
      ast = build_ast('2 -3')
      ast.must_equal [[:send, [:integer, '2'], '-', [[:integer, '3']]]]
      ast = build_ast('2 + -3')
      ast.must_equal [[:send, [:integer, '2'], '+', [[:integer, '-3']]]]
      ast = build_ast('9223372036854775807') # max 64-bit signed integer
      ast.must_equal [[:integer, '9223372036854775807']]
    end

    it 'parses multiple expressions' do
      ast = build_ast("1\n2")
      ast.must_equal [[:integer, '1'], [:integer, '2']]
      ast = build_ast("1 \n 2")
      ast.must_equal [[:integer, '1'], [:integer, '2']]
      ast = build_ast("1;2")
      ast.must_equal [[:integer, '1'], [:integer, '2']]
      ast = build_ast("1 ; 2")
      ast.must_equal [[:integer, '1'], [:integer, '2']]
    end

    it 'parses strings' do
      ast = build_ast('"a"')
      ast.must_equal [[:string, 'a']]
      ast = build_ast("'a'")
      ast.must_equal [[:string, 'a']]
    end

    it 'parses operator method calls' do
      ast = build_ast("x * 2")
      ast.must_equal [[:send, [:send, nil, 'x', []], '*', [[:integer, '2']]]]
      ast = build_ast("x.to_s + 'x'")
      ast.must_equal [[:send, [:send, [:send, nil, 'x', []], 'to_s', []], '+', [[:string, 'x']]]]
      ast = build_ast("puts x.to_s + 'x'")
      ast.must_equal [[:send, nil, 'puts', [[:send, [:send, [:send, nil, 'x', []], 'to_s', []], '+', [[:string, 'x']]]]]]
      ast = build_ast("'a' << 'b'")
      ast.must_equal [[:send, [:string, 'a'], '<<', [[:string, 'b']]]]
      ast = build_ast("'a' << 'b' << 'c'")
      ast.must_equal [[:send, [:string, "a"], "<<", [[:send, [:string, "b"], "<<", [[:string, "c"]]]]]]
      ast = build_ast("'a'.<< 'b'")
      ast.must_equal [[:send, [:string, 'a'], '<<', [[:string, 'b']]]]
      ast = build_ast("'a'.<<('b')")
      ast.must_equal [[:send, [:string, 'a'], '<<', [[:string, 'b']]]]
      ast = build_ast("'a'.<<('b', 'c')")
      ast.must_equal [[:send, [:string, 'a'], '<<', [[:string, 'b'], [:string, 'c']]]]
    end

    it 'parses method calls with a dot' do
      ast = build_ast("'a'.upcase")
      ast.must_equal [[:send, [:string, 'a'], 'upcase', []]]
      ast = build_ast("'a'.upcase.strip")
      ast.must_equal [[:send, [:send, [:string, 'a'], 'upcase', []], 'strip', []]]
      ast = build_ast("'a'.upcase.include?('a')")
      ast.must_equal [[:send, [:send, [:string, 'a'], 'upcase', []], 'include?', [[:string, 'a']]]]
      ast = build_ast("'a'.upcase.include? 'a'")
      ast.must_equal [[:send, [:send, [:string, 'a'], 'upcase', []], 'include?', [[:string, 'a']]]]
    end

    it 'parses method calls without a dot' do
      ast = build_ast("foo")
      ast.must_equal [[:send, nil, 'foo', []]]
      ast = build_ast("foo 'bar'")
      ast.must_equal [[:send, nil, 'foo', [[:string, 'bar']]]]
      ast = build_ast("foo('bar', 'baz')")
      ast.must_equal [[:send, nil, 'foo', [[:string, 'bar'], [:string, 'baz']]]]
      ast = build_ast("foo.upcase")
      ast.must_equal [[:send, [:send, nil, 'foo', []], 'upcase', []]]
    end

    it 'parses assignments' do
      ast = build_ast("x = 1")
      ast.must_equal [[:assign, 'x', [:integer, '1']]]
      ast = build_ast("num=1")
      ast.must_equal [[:assign, 'num', [:integer, '1']]]
      ast = build_ast("message_upcase = 'hi'.upcase")
      ast.must_equal [[:assign, 'message_upcase', [:send, [:string, 'hi'], 'upcase', []]]]
    end

    it 'parses method definitions' do
      ast = build_ast("def foo; end")
      ast.must_equal [[:def, 'foo', [], {}, []]]
      ast = build_ast("def foo; 'foo'; end")
      ast.must_equal [[:def, 'foo', [], {}, [[:string, 'foo']]]]
      ast = build_ast("def foo \n 'foo'\n 2 \n 'bar'\n end")
      ast.first.first.must_equal :def
      ast = build_ast("def foo(x); x; end")
      ast.must_equal [[:def, 'foo', ['x'], {}, [[:send, nil, 'x', []]]]]
      ast = build_ast("def foo(x, y); x; end")
      ast.must_equal [[:def, 'foo', ['x', 'y'], {}, [[:send, nil, 'x', []]]]]
      ast = build_ast("def foo x  ; x; end")
      ast.must_equal [[:def, 'foo', ['x'], {}, [[:send, nil, 'x', []]]]]
      ast = build_ast("def foo   x, y; x; end")
      ast.must_equal [[:def, 'foo', ['x', 'y'], {}, [[:send, nil, 'x', []]]]]
    end

    it 'parses class definitions' do
      ast = build_ast("class Foo; end")
      ast.must_equal [[:class, 'Foo', nil, []]]
      ast = build_ast("class Foo < Bar; end")
      ast.must_equal [[:class, 'Foo', 'Bar', []]]
      ast = build_ast("class Foo; def foo; end; end")
      ast.must_equal [[:class, 'Foo', nil, [[:def, 'foo', [], {}, []]]]]
      ast = build_ast("class Foo; x = 1; end")
      ast.must_equal [[:class, 'Foo', nil, [[:assign, 'x', [:integer, '1']]]]]
    end

    it 'parses array literals' do
      ast = build_ast("[]")
      ast.must_equal [[:array, []]]
      ast = build_ast("[1]")
      ast.must_equal [[:array, [[:integer, '1']]]]
      ast = build_ast("[  1  ]")
      ast.must_equal [[:array, [[:integer, '1']]]]
      ast = build_ast("[  \n1\n  ]")
      ast.must_equal [[:array, [[:integer, '1']]]]
      ast = build_ast("[  \n1\n,\n2,3,   \n 4  ]")
      ast.must_equal [[:array, [[:integer, '1'], [:integer, '2'], [:integer, '3'], [:integer, '4']]]]
      ast = build_ast("[  \n1\n,\n2,3,   \n [4]  ]")
      ast.must_equal [[:array, [[:integer, '1'], [:integer, '2'], [:integer, '3'], [:array, [[:integer, '4']]]]]]
    end

    it 'parses array subscript syntax' do
      ast = build_ast("foo[0]")
      ast.must_equal [[:send, [:send, nil, 'foo', []], '[]', [[:integer, '0']]]]
    end

    it 'parses modules' do
      ast = build_ast('module M; end')
      ast.must_equal [[:module, 'M', []]]
      ast = build_ast('module M; def m; "m"; end; end')
      ast.must_equal [[:module, 'M', [[:def, 'm', [], {}, [[:string, 'm']]]]]]
    end

    it 'ignores comments' do
      ast = build_ast('1 # comment')
      ast.must_equal [[:integer, '1']]
      ast = build_ast('1; 2 # comment')
      ast.must_equal [[:integer, '1'], [:integer, '2']]
      ast = build_ast('1; 2; # comment')
      ast.must_equal [[:integer, '1'], [:integer, '2']]
      ast = build_ast("1\n2 # comment\n3")
      ast.must_equal [[:integer, '1'], [:integer, '2'], [:integer, '3']]
      ast = build_ast("# ignore me\n# ignore me again\n1")
      ast.must_equal [[:integer, '1']]
      ast = build_ast('# comment')
      ast.must_equal []
      ast = build_ast("class Foo; end # comment")
      ast.must_equal [[:class, 'Foo', nil, []]]
      ast = build_ast("class Foo\nend # comment")
      ast.must_equal [[:class, 'Foo', nil, []]]
      ast = build_ast("class Bar # foo\n end")
      ast.must_equal [[:class, 'Bar', nil, []]]
      ast = build_ast("module Bar # foo\n end")
      ast.must_equal [[:module, 'Bar', []]]
      ast = build_ast("def bar # foo\n end")
      ast.must_equal [[:def, 'bar', [], {}, []]]
    end

    it 'parses symbols' do
      ast = build_ast(':foo')
      ast.must_equal [[:symbol, 'foo']]
      ast = build_ast(':Bar')
      ast.must_equal [[:symbol, 'Bar']]
    end
  end
end
