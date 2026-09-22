module Finance
  # Répartit autrement un règlement DÉJÀ encodé (Michael, 2026-09-20).
  #
  # Le cas qui l'a fait naître : chez Seb, 280 € versés chaque mois payaient
  # 230 € de charges et 50 € de location du dôme. La reprise n'avait qu'un poste
  # à donner à chaque règlement et a tout mis sur les charges. Résultat, depuis
  # que le lettrage se fait poste par poste : 2 100 € de dôme réclamés en face
  # de 2 260 € d'avance sur les charges, pour de l'argent bel et bien versé.
  #
  # Ce service NE TOUCHE PAS AU MONTANT. Il ne crée ni n'efface d'argent : il
  # redécoupe l'encaissement, et la somme des morceaux doit valoir exactement
  # ce qu'elle valait. C'est la seule garantie qui compte ici — un service de
  # correction qui peut changer un solde est un service qui finira par le faire.
  #
  # Les anciennes écritures sont SUPPRIMÉES et remplacées, pas contre-écrites :
  # une ventilation n'est pas une erreur de fait à laisser dans l'historique,
  # c'est le même argent mieux rangé, et PaperTrail garde la trace. Une écriture
  # rattachée à un décompte émis est verrouillée : le service refuse alors de
  # toucher au règlement plutôt que de faire mentir un décompte déjà envoyé.
  class ReventilateSettlement < ServiceBase
    class Mismatch < StandardError; end
    class Locked < StandardError; end

    def initialize(settlement:, ventilation:, whodunnit: nil)
      @settlement = settlement
      @ventilation = ventilation.transform_values(&:to_i).reject { |_, cents| cents.zero? }
      @whodunnit = whodunnit
    end

    def run = catch_error(context: { settlement: @settlement&.id }) { reventilate }
    def run! = reventilate

    private

    def reventilate
      verifie!

      PaperTrail.request(whodunnit: @whodunnit || "reventilation") do
        ApplicationRecord.transaction do
          compte = @settlement.member_account
          modele = ecritures.first

          @settlement.update!(account_entry: nil)
          ecritures.each(&:destroy!)

          creees = @ventilation.map do |poste, cents|
            compte.account_entries.create!(
              entry_date: modele.entry_date,
              posted_at: Time.current,
              amount_cents: -cents.abs,
              kind: "settlement",
              flow: poste,
              source: modele.source,
              label: libelle(modele, poste),
              account_settlement: @settlement
            )
          end

          @settlement.update!(account_entry: creees.first)
          @settlement
        end
      end
    end

    def verifie!
      raise Mismatch, "Ce règlement ne porte aucune écriture à ventiler." if ecritures.empty?
      raise Locked, "Une écriture de ce règlement est rattachée à un décompte émis." if ecritures.any?(&:locked?)

      total = @ventilation.values.sum(&:abs)
      return if total == @settlement.amount_cents.abs

      raise Mismatch,
            "La ventilation totalise #{Money.new(total, 'EUR').format} " \
            "pour un règlement de #{Money.new(@settlement.amount_cents.abs, 'EUR').format}."
    end

    # Les écritures du règlement, par le lien de ventilation ou, pour tout ce
    # qui date d'avant lui, par l'écriture principale.
    def ecritures
      @ecritures ||= begin
        liees = @settlement.account_entries.to_a
        liees.presence || [@settlement.account_entry].compact
      end
    end

    # Le libellé d'origine, débarrassé du poste déjà accolé par une ventilation
    # précédente, puis suffixé du nouveau — seulement s'il y a plusieurs postes.
    # Seul un suffixe qui EST un nom de poste est retiré : « Règlement —
    # Virement » n'en est pas un, et se faisait amputer de son moyen de
    # paiement.
    SUFFIXE_DE_POSTE = /\s+—\s+(#{Regexp.union(AccountEntry::FLOW_LABELS.values)})\z/

    def libelle(modele, poste)
      base = modele.label.to_s.sub(SUFFIXE_DE_POSTE, "").presence || "Règlement"
      return base if @ventilation.size == 1

      "#{base} — #{AccountEntry::FLOW_LABELS.fetch(poste, poste)}"
    end
  end
end
