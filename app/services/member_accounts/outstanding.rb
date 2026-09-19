module MemberAccounts
  # « Je ne vois pas à quoi correspond le montant impayé » (Michael, 2026-08-19).
  #
  # Le solde d'un compte est une somme algébrique : consommations en positif,
  # règlements en négatif. Affiché nu, il ne dit rien — 665,08 € peut être un
  # mois oublié comme trois ans de dérive. Ce service refait le lettrage que
  # personne ne tient à la main : chaque règlement s'impute sur les dettes les
  # plus anciennes encore ouvertes, et ce qui reste debout EST la réponse.
  #
  # L'imputation est chronologique et non destructive — rien n'est écrit en
  # base. C'est une LECTURE du grand livre, pas un lettrage comptable : deux
  # personnes qui l'ouvrent voient la même chose, et un règlement encodé demain
  # rebat les cartes sans qu'aucune donnée n'ait à être corrigée.
  class Outstanding
    BAR_FLOW = "bar".freeze

    # Une ligne encore due : ce qu'il en reste après imputation des règlements,
    # pas son montant d'origine.
    Ligne = Struct.new(:entry_date, :label, :flow, :amount_cents, :note, keyword_init: true) do
      def flow_label = AccountEntry::FLOW_LABELS[flow]

      # Ce qui se lit en petit à droite du libellé : le canal d'ordinaire, le
      # nombre de consommations quand la ligne en résume plusieurs.
      def detail = note.presence || flow_label
    end

    # Un mois de consommation non couverte.
    Poste = Struct.new(:month, :amount_cents, :lignes, keyword_init: true)

    def initialize(member_account)
      @account = member_account
    end

    # Les mois encore dus, du plus ancien au plus récent — l'ordre dans lequel
    # les règlements viendront les éteindre.
    def postes
      calcul[:postes]
    end

    # Ce qui reste à payer. Vaut `balance_cents` quand le compte est débiteur ;
    # zéro quand il est à jour ou en avance.
    def total_cents
      calcul[:total_cents]
    end

    # Un règlement encaissé au-delà des consommations connues. Le contraire
    # d'une dette, et la seule autre façon d'expliquer un solde.
    def advance_cents
      calcul[:advance_cents]
    end

    def any?
      total_cents.positive?
    end

    # Depuis quand le compte n'est plus à zéro. « Impayé depuis mars 2024 » se
    # comprend d'un coup d'œil là où une somme reste muette.
    def oldest_month
      postes.first&.month
    end

    private

    # Le solde d'ouverture est une dette comme une autre : il entre dans la file
    # à sa date, sinon un compte repris avec un arriéré afficherait un total
    # inférieur à son solde.
    def calcul
      @calcul ||= begin
        ouverts = []
        reserve = 0

        mouvements.each do |mouvement|
          if mouvement.amount_cents.positive?
            reste = mouvement.amount_cents
            impute = [reserve, reste].min
            reserve -= impute
            reste -= impute
            ouverts << mouvement.dup.tap { |m| m.amount_cents = reste } if reste.positive?
          else
            reserve += eteindre(ouverts, -mouvement.amount_cents)
          end
        end

        { postes: regrouper(ouverts),
          total_cents: ouverts.sum(&:amount_cents),
          advance_cents: reserve }
      end
    end

    # Impute un règlement sur les dettes ouvertes les plus anciennes ; rend ce
    # qui n'a rien trouvé à éteindre.
    def eteindre(ouverts, montant)
      ouverts.each do |ligne|
        break if montant.zero?

        impute = [ligne.amount_cents, montant].min
        ligne.amount_cents -= impute
        montant -= impute
      end
      ouverts.reject! { |ligne| ligne.amount_cents.zero? }
      montant
    end

    def mouvements
      @mouvements ||= [ouverture, *ecritures].compact
    end

    def ouverture
      return nil unless @account.opening_balance_cents != 0

      Ligne.new(entry_date: @account.opening_balance_on || @account.created_at.to_date,
                label: "Solde repris à l'ouverture du compte",
                flow: nil,
                amount_cents: @account.opening_balance_cents)
    end

    def ecritures
      @account.account_entries.chronological.map do |entry|
        Ligne.new(entry_date: entry.entry_date, label: entry.label.presence || entry.flow_label,
                  flow: entry.flow, amount_cents: entry.amount_cents)
      end
    end

    def regrouper(ouverts)
      ouverts.group_by { |ligne| ligne.entry_date.beginning_of_month }
             .sort_by(&:first)
             .map do |month, lignes|
               Poste.new(month: month, amount_cents: lignes.sum(&:amount_cents),
                         lignes: replier_le_bar(lignes).sort_by(&:entry_date))
             end
    end

    # Le bar se lit en UNE ligne (Michael, 2026-09-19). Un mois de bar, c'est
    # trente consommations à 1,95 € ; déroulées ici, elles noient les charges et
    # le loyer — qui sont ce qu'on vient chercher. Le détail ne disparaît pas :
    # il reste entier dans le grand livre, juste en dessous sur la même page.
    #
    # Une consommation seule n'est pas un groupe : la replier remplacerait
    # « Chips ReBel » par « Bar » sans rien faire gagner. Même règle que
    # `GroupedLedger`, pour que les deux blocs de la page se lisent pareil.
    def replier_le_bar(lignes)
      bar, reste = lignes.partition { |ligne| ligne.flow == BAR_FLOW }
      return lignes if bar.size <= 1

      reste << Ligne.new(entry_date: bar.map(&:entry_date).min,
                         label: AccountEntry::FLOW_LABELS.fetch(BAR_FLOW),
                         flow: BAR_FLOW,
                         amount_cents: bar.sum(&:amount_cents),
                         note: "#{bar.size} consommations")
    end
  end
end
