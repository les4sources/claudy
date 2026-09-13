module ExpenseReports
  # Le passage en traitement (epic #241, phase 1).
  #
  # C'est LE moment où la note devient un document comptable : elle reçoit son
  # numéro de pièce, l'écriture d'achat sort, et plus rien de ce qui décrit la
  # dépense ne bouge. Les trois vont ensemble ou aucun des trois — d'où la
  # transaction.
  #
  # Le verrou est sur l'EXERCICE et il précède le calcul du numéro, exactement
  # comme dans `Accounting::PostDocument` : sans lui, deux passages simultanés
  # prennent le même numéro et l'index unique en fait échouer un au hasard.
  class Process < ServiceBase
    class BadStatus < StandardError; end
    class NoLines < StandardError; end
    class MissingFiscalYear < StandardError; end

    def initialize(expense_report:, processed_on: nil, whodunnit: nil)
      @report = expense_report
      @processed_on = processed_on.presence
      @whodunnit = whodunnit
    end

    def run
      catch_error(context: { expense_report: @report.id }) { process }
    end

    def run! = process

    private

    def process
      unless @report.recorded?
        raise BadStatus,
              "Seule une note enregistrée passe en traitement — celle-ci est " \
              "#{@report.status_label.downcase}."
      end
      raise NoLines, "Ajoute au moins une ligne avant de passer la note en traitement." if @report.expense_lines.empty?

      date = parsed_date

      # Une note déjà numérotée garde SON numéro et SON exercice — une note
      # contre-passée puis corrigée repasse ici, et réattribuer un numéro
      # laisserait un trou dans la séquence (décision 4 : jamais réattribué).
      fiscal_year = @report.sequence_number.present? ? @report.fiscal_year : @report.legal_entity.fiscal_year_for(date)
      if fiscal_year.blank? || !fiscal_year.covers?(date)
        raise MissingFiscalYear,
              "Aucun exercice ouvert ne couvre le #{I18n.l(date)} pour " \
              "#{@report.legal_entity.name} — crée l'exercice avant de comptabiliser."
      end

      PaperTrail.request(whodunnit: @whodunnit || "expense_reports") do
        ApplicationRecord.transaction do
          fiscal_year.lock!

          number = @report.sequence_number ||
                   ExpenseReport.next_sequence_number(fiscal_year_id: fiscal_year.id, kind: @report.kind)
          @report.update!(
            status: "processing",
            processed_on: date,
            fiscal_year: fiscal_year,
            sequence_number: number,
            reference: @report.reference.presence ||
                       ExpenseReport.format_reference(prefix: @report.reference_prefix,
                                                      year: fiscal_year.starts_on.year,
                                                      number: number)
          )

          entry = Accounting::PostExpenseReport.new(expense_report: @report, whodunnit: @whodunnit).run!
          @report.update!(posted_at: Time.current)
          entry
        end
      end

      @report.reload
    end

    def parsed_date
      return Date.current if @processed_on.blank?

      @processed_on.is_a?(String) ? Date.parse(@processed_on) : @processed_on
    end
  end
end
