module Accounting
  # L'écriture d'une note de frais (epic #241, phase 1).
  #
  # Une note de frais est un ACHAT au sens comptable : quelqu'un a avancé de
  # l'argent pour la structure, la structure le lui doit. D'où le journal
  # `purchases`, les charges au débit — une ligne d'écriture par ligne de note,
  # avec son pôle — et la dette au crédit du 440000, portée par le tiers du
  # bénéficiaire. C'est cette ligne-là qu'on lettrera contre le virement.
  #
  # Idempotent par construction : `PostDocument` rend l'écriture existante quand
  # le même document repasse dans le même journal.
  class PostExpenseReport < ServiceBase
    class MissingAccount < StandardError; end
    class NoLines < StandardError; end

    SUPPLIER_CODE = "440000".freeze

    def initialize(expense_report:, whodunnit: nil)
      @report = expense_report
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { expense_report: @report.id }) { post }
    end

    def run! = post

    private

    def post
      lines = @report.expense_lines.chronological.to_a
      raise NoLines, "Cette note n'a aucune ligne — il n'y a rien à comptabiliser." if lines.empty?

      PostDocument.new(
        legal_entity: @report.legal_entity,
        journal: "purchases",
        entry_date: @report.processed_on || Date.current,
        label: label,
        source: @report,
        whodunnit: @whodunnit,
        lines: debit_lines(lines) + [credit_line(lines)]
      ).run!
    end

    def label
      "#{@report.kind_label} #{@report.reference} — #{@report.human&.name}"
    end

    # Une ligne d'écriture par ligne de note, et pas un total : c'est ce qui
    # permet à la balance analytique de dire quel pôle a dépensé quoi. Fusionner
    # les lignes ferait gagner trois lignes au grand livre et perdre toute
    # l'information qui sert à décider.
    def debit_lines(lines)
      lines.map do |line|
        {
          account: line.general_account || raise(MissingAccount,
                                                 "La ligne « #{line.label} » n'a pas de compte de charge."),
          analytic_account: line.analytic_account,
          team: line.team,
          label: line_label(line),
          debit_cents: line.amount_cents
        }
      end
    end

    def credit_line(lines)
      {
        account: supplier_account,
        third_party: ThirdParty.for_human!(@report.human),
        label: label,
        credit_cents: lines.sum(&:amount_cents)
      }
    end

    def line_label(line)
      [line.supplier_name.presence, line.label].compact.join(" — ")
    end

    def supplier_account
      GeneralAccount.find_by(code: SUPPLIER_CODE) ||
        raise(MissingAccount,
              "Le compte #{SUPPLIER_CODE} n'existe pas — lance `rake accounting:seed_reference`.")
    end
  end
end
