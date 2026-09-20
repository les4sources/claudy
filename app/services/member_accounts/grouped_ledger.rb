module MemberAccounts
  # Le grand livre d'un compte, replié à la maille où il se lit.
  #
  # Le compte de Béné porte 501 écritures : chaque bière, chaque café, chaque
  # bouteille. Déroulées une par une, elles ne disent plus rien — personne ne
  # lit cinquante lignes pour savoir ce que le bar a coûté en juillet. Une
  # ligne « Bar — juillet 2026 » et son total, oui (Michael, 2026-08-19).
  #
  # Deux règles, et elles ne sont pas symétriques :
  #
  # 1. Les CONSOMMATIONS se replient par mois et par canal. Le détail reste
  #    accessible, mais il n'est plus ce qu'on lit en premier.
  # 2. Les RÈGLEMENTS ne se replient jamais. Un virement de 350 € est un
  #    événement daté qu'on vient vérifier ; fondu dans un total mensuel, il
  #    devient précisément ce qu'on ne peut plus retrouver.
  class GroupedLedger
    Groupe = Struct.new(:cle, :month, :flow, :amount_cents, :entries, keyword_init: true) do
      # Un groupe d'une seule écriture n'est pas un groupe : l'afficher replié
      # ajouterait un clic pour révéler la ligne qu'on voyait déjà.
      def replie? = entries.size > 1

      def entree = entries.first

      def label
        return entree.label.presence || libelle_canal if entries.one?

        libelle_canal
      end

      # Un règlement n'a PAS de canal. Un virement de 345 € n'est ni du bar ni
      # des charges : il éteint ce qu'il trouve de plus ancien, et il peut très
      # bien couvrir trois postes à la fois. `RecordSettlement` lui pose donc
      # `flow: "other"`, ce qui affichait « Divers » — un mot qui n'apprend rien
      # là où « Règlement » dit exactement ce qu'on regarde (Michael,
      # 2026-09-20). On nomme la NATURE de l'écriture quand elle n'a pas de
      # poste ; pour tout le reste, le canal reste le canal.
      SANS_CANAL = %w[settlement payout reversal].freeze

      def libelle_canal
        return AccountEntry::KIND_LABELS.fetch(entree.kind) if sans_canal?

        AccountEntry::FLOW_LABELS.fetch(flow, "Divers")
      end

      def sans_canal? = entries.one? && SANS_CANAL.include?(entree.kind)

      def date_de_tri = entries.first.entry_date
    end

    def initialize(account_entries)
      @entries = account_entries
    end

    # Du plus récent au plus ancien, comme la table qu'il remplace.
    def groupes
      @groupes ||= (consommations + reglements).sort_by { |g| [-g.date_de_tri.to_time.to_i, -g.amount_cents.abs] }
    end

    def any? = groupes.any?

    private

    def entries = @liste ||= @entries.to_a

    def consommations
      entries.reject { |e| e.amount_cents.negative? }
             .group_by { |e| [e.entry_date.beginning_of_month, e.flow] }
             .map do |(month, flow), lignes|
               triees = lignes.sort_by { |e| [-e.entry_date.to_time.to_i, -e.id] }
               Groupe.new(cle: "#{month.strftime('%Y-%m')}-#{flow || 'sans'}", month: month, flow: flow,
                          amount_cents: triees.sum(&:amount_cents), entries: triees)
             end
    end

    def reglements
      entries.select { |e| e.amount_cents.negative? }.map do |entry|
        Groupe.new(cle: "reglement-#{entry.id}", month: entry.entry_date.beginning_of_month,
                   flow: entry.flow, amount_cents: entry.amount_cents, entries: [entry])
      end
    end
  end
end
