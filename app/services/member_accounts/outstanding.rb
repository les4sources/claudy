module MemberAccounts
  # « Je ne vois pas à quoi correspond le montant impayé » (Michael, 2026-08-19).
  #
  # Le solde d'un compte est une somme algébrique : consommations en positif,
  # règlements en négatif. Affiché nu, il ne dit rien — 665,08 € peut être un
  # mois oublié comme trois ans de dérive. Ce service refait le lettrage que
  # personne ne tient à la main, et ce qui reste debout EST la réponse.
  #
  # LE LETTRAGE SE FAIT POSTE PAR POSTE (Michael, 2026-09-20). « Quand on fait
  # un paiement de 345 €, c'est pour payer nos charges habitants, pas pour
  # régler d'autres dettes bar ou batchcooking. Sinon on ne s'y retrouve plus. »
  # Un règlement éteint donc les dettes du POSTE qu'il paie, les plus anciennes
  # d'abord — jamais celles d'un autre poste. Avant ça, l'imputation était
  # chronologique tous postes confondus, et un virement de charges partait
  # éponger des bières de juin : le foyer voyait ses charges du mois réclamées
  # alors qu'il venait de les payer.
  #
  # Un excédent sur un poste NE DÉBORDE PAS sur les autres. Il reste une avance
  # sur ce poste. C'est ce qui rend les anomalies visibles : un compte à jour
  # partout sauf 600 € d'avance sur les charges raconte quelque chose qu'un
  # solde global lissé aurait tu.
  #
  # L'imputation est non destructive — rien n'est écrit en base. C'est une
  # LECTURE du grand livre, pas un lettrage comptable : deux personnes qui
  # l'ouvrent voient la même chose, et un règlement encodé demain rebat les
  # cartes sans qu'aucune donnée n'ait à être corrigée.
  #
  # Tout repose sur une condition : que le règlement PORTE le poste qu'il paie,
  # dans son `flow`. `Finance::RecordSettlement` le pose à l'encodage ;
  # l'historique a été repris par `rake finance:backfill_settlement_flows`.
  # Un règlement sans poste identifié tombe dans « Divers », où il n'éteint que
  # du « Divers » — visible, donc réparable.
  class Outstanding
    # L'ordre d'affichage. Fixe, pas trié par montant : un tableau dont les
    # lignes changent de place d'un compte à l'autre se relit à chaque fois.
    POSTES = (AccountEntry::FLOWS - ["other"]) + ["other"]
    SANS_POSTE = "other".freeze

    # Une ligne encore due : ce qu'il en reste après imputation des règlements,
    # pas son montant d'origine.
    Ligne = Struct.new(:entry_date, :label, :flow, :amount_cents, keyword_init: true) do
      def flow_label = AccountEntry::FLOW_LABELS[flow]
    end

    # Un poste et ce qu'il doit encore. `advance_cents` est son contraire : ce
    # qui a été versé au-delà de ce que le poste réclamait.
    Poste = Struct.new(:flow, :amount_cents, :advance_cents, :lignes, keyword_init: true) do
      def label = AccountEntry::FLOW_LABELS.fetch(flow, "Divers")
      def any? = amount_cents.positive?
      def oldest_on = lignes.first&.entry_date
    end

    def initialize(member_account)
      @account = member_account
    end

    # Les postes encore dus, dans l'ordre canonique. Un poste soldé n'y est pas.
    def postes
      calcul[:postes]
    end

    # Les postes en avance — un règlement encaissé au-delà de ce que le poste
    # réclamait. Rare, et c'est justement ce qui fait qu'on ne le voit jamais.
    def avances
      calcul[:avances]
    end

    # Ce qui reste à payer, tous postes confondus.
    def total_cents
      calcul[:total_cents]
    end

    def advance_cents
      calcul[:advance_cents]
    end

    def any?
      total_cents.positive?
    end

    # Le mois de la plus ancienne dette encore ouverte, tous postes confondus.
    def oldest_month
      postes.filter_map(&:oldest_on).min&.beginning_of_month
    end

    # Le détail d'UN poste, pour la fenêtre qui s'ouvre au clic sur son montant.
    def poste(flow)
      postes.find { |p| p.flow == flow }
    end

    private

    def calcul
      @calcul ||= begin
        ouverts = Hash.new { |hash, key| hash[key] = [] }
        reserves = Hash.new(0)

        mouvements.group_by { |ligne| ligne.flow.presence || SANS_POSTE }
                  .each { |poste, lignes| reserves[poste] = imputer(lignes, ouverts[poste]) }

        { postes: assembler(ouverts, reserves),
          avances: reserves.select { |_, cents| cents.positive? },
          total_cents: ouverts.values.sum { |lignes| lignes.sum(&:amount_cents) },
          advance_cents: reserves.values.sum }
      end
    end

    # Le FIFO d'un seul poste : chaque règlement éteint les dettes les plus
    # anciennes du poste, et ce qui ne trouve rien à éteindre devient une avance
    # sur ce poste — pas sur le compte.
    def imputer(lignes, ouverts)
      reserve = 0

      lignes.each do |mouvement|
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

      reserve
    end

    # Impute un règlement sur les dettes ouvertes les plus anciennes du poste ;
    # rend ce qui n'a rien trouvé à éteindre.
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

    def assembler(ouverts, reserves)
      POSTES.filter_map do |flow|
        lignes = ouverts[flow]
        next if lignes.empty?

        Poste.new(flow: flow, amount_cents: lignes.sum(&:amount_cents),
                  advance_cents: reserves[flow], lignes: lignes.sort_by(&:entry_date))
      end
    end

    def mouvements
      @mouvements ||= [ouverture, *ecritures].compact
    end

    # Le solde d'ouverture est une dette comme une autre : il entre dans la file
    # à sa date, sinon un compte repris avec un arriéré afficherait un total
    # inférieur à son solde. Faute de poste, il tombe dans « Divers ».
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
  end
end
