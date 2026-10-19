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
  #
  # C'est aussi ici que la compta attribue le compte de charge de chaque ligne
  # (Michael, 2026-10-18) : `accounts` = { id de ligne => id de compte }. Les
  # comptes s'enregistrent AVANT le passage, hors de sa transaction : si
  # l'exercice manque, le choix fait ligne par ligne n'est pas perdu.
  #
  # Le pôle de chaque ligne se corrige au même moment (Michael, 2026-10-19) :
  # `teams` = { id de ligne => id de pôle, ou vide pour « aucun pôle » }. C'est
  # lui que l'écriture porte, et lui que lisent les comptes du pôle.
  class Process < ServiceBase
    class BadStatus < StandardError; end
    class NoLines < StandardError; end
    class MissingFiscalYear < StandardError; end
    class MissingAccount < StandardError; end
    class UnknownTeam < StandardError; end

    def initialize(expense_report:, processed_on: nil, accounts: nil, teams: nil, whodunnit: nil)
      @report = expense_report
      @processed_on = processed_on.presence
      @accounts = (accounts || {}).to_h.transform_keys(&:to_s)
      @teams = (teams || {}).to_h.transform_keys(&:to_s)
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
      assign_accounts
      assign_teams
      ensure_accounts

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

    def assign_accounts
      return if @accounts.empty?

      allowed = ExpenseLine.assignable_accounts.where(id: @accounts.values.compact_blank).index_by { |a| a.id.to_s }
      PaperTrail.request(whodunnit: @whodunnit || "expense_reports") do
        @report.expense_lines.each do |line|
          next unless @accounts.key?(line.id.to_s)

          chosen = @accounts[line.id.to_s].to_s
          account = allowed[chosen]
          if chosen.present? && account.nil?
            raise MissingAccount, "Le compte choisi pour « #{line.label} » n'est pas un compte de charge ou d'immobilisation actif."
          end

          line.update!(general_account: account) unless line.general_account_id == account&.id
        end
      end
    end

    # Une clé présente et vide = « aucun pôle » : la part reste non ventilée.
    def assign_teams
      return if @teams.empty?

      known = Team.where(id: @teams.values.compact_blank).index_by { |t| t.id.to_s }
      PaperTrail.request(whodunnit: @whodunnit || "expense_reports") do
        @report.expense_lines.each do |line|
          next unless @teams.key?(line.id.to_s)

          chosen = @teams[line.id.to_s].to_s
          team = known[chosen]
          raise UnknownTeam, "Le pôle choisi pour « #{line.label} » n'existe pas." if chosen.present? && team.nil?

          line.update!(team: team) unless line.team_id == team&.id
        end
      end
    end

    def ensure_accounts
      missing = @report.expense_lines.reject(&:general_account_id)
      return if missing.empty?

      raise MissingAccount,
            "Attribue un compte de charge à chaque ligne avant de traiter la note — il manque : " \
            "#{missing.map { |line| "« #{line.label} »" }.join(', ')}."
    end

    def parsed_date
      return Date.current if @processed_on.blank?

      @processed_on.is_a?(String) ? Date.parse(@processed_on) : @processed_on
    end
  end
end
