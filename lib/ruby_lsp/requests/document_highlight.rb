# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Document highlight demo](../../misc/document_highlight.gif)
    #
    # The [document highlight](https://microsoft.github.io/language-server-protocol/specification#textDocument_documentHighlight)
    # informs the editor all relevant elements of the currently pointed item for highlighting. For example, when
    # the cursor is on the `F` of the constant `FOO`, the editor should identify other occurences of `FOO`
    # and highlight them.
    #
    # For writable elements like constants or variables, their read/write occurrences should be highlighted differently.
    # This is achieved by sending different "kind" attributes to the editor (2 for read and 3 for write).
    #
    # # Example
    #
    # ```ruby
    # FOO = 1 # should be highlighted as "write"
    #
    # def foo
    #   FOO # should be highlighted as "read"
    # end
    # ```
    class DocumentHighlight < BaseRequest
      extend T::Sig

      VarNodes = T.type_alias do
        T.any(
          SyntaxTree::GVar,
          SyntaxTree::Ident,
          SyntaxTree::IVar,
          SyntaxTree::Const,
          SyntaxTree::CVar
        )
      end

      sig { params(document: Document, position: Document::PositionShape).void }
      def initialize(document, position)
        @highlights = T.let([], T::Array[LanguageServer::Protocol::Interface::DocumentHighlight])
        position = Document::Scanner.new(document.source).find_position(position)
        @target = T.let(find(T.must(document.tree), position), T.nilable(VarNodes))

        super(document)
      end

      sig { override.returns(T.all(T::Array[LanguageServer::Protocol::Interface::DocumentHighlight], Object)) }
      def run
        # no @target means the target is not highlightable
        return [] unless @target

        visit(@document.tree)
        @highlights
      end

      sig { params(node: T.nilable(SyntaxTree::Node)).void }
      def visit(node)
        return if node.nil?

        type = T.must(@target).highlight_type(node)
        add_highlight(node, type) if type

        super
      end

      private

      sig do
        params(
          node: SyntaxTree::Node,
          position: Integer,
          parent: T.nilable(SyntaxTree::Node)
        ).returns(T.nilable(Support::HighlightTarget))
      end
      def find(node, position, parent = nil)
        matched =
          node.child_nodes.compact.bsearch do |child|
            if (child.location.start_char...child.location.end_char).cover?(position)
              0
            else
              position <=> child.location.start_char
            end
          end

        case matched
        when SyntaxTree::GVar, SyntaxTree::IVar, SyntaxTree::Const, SyntaxTree::CVar, SyntaxTree::VarField
          Support::HighlightTarget.new(matched)
        when SyntaxTree::Ident
          Support::HighlightTarget.new(T.must(parent))
        when SyntaxTree::Node
          find(matched, position, node)
        end
      end

      sig { params(node: SyntaxTree::Node, kind: Integer).void }
      def add_highlight(node, kind)
        range = range_from_syntax_tree_node(node)
        @highlights << LanguageServer::Protocol::Interface::DocumentHighlight.new(range: range, kind: kind)
      end
    end
  end
end
