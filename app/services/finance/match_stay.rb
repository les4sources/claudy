module Finance
  # Propose le séjour qu'une ligne de trésorerie paie (issue #185).
  #
  # Une cascade ORDONNÉE, du plus certain au plus faible, et chaque niveau porte
  # son motif. L'ordre n'est pas cosmétique : une communication qui nomme le
  # séjour est une preuve, un montant qui tombe juste est une coïncidence
  # probable. Les traiter pareil, c'est finir par attribuer la recette d'un
  # client à un autre.
  #
  # **Deux candidats à égalité ne proposent RIEN.** C'est la règle qui coûte le
  # plus en confort et rapporte le plus en confiance : deviner ici produit une
  # erreur qu'on ne verra jamais, parce que les deux montants sont justes et que
  # seul le nom du client est faux.
  class MatchStay < ServiceBase
    Match = Struct.new(:stay, :confidence, :rationale, keyword_init: true)

    OPEN_STATUSES = %w[pending partially_paid].freeze

    # `open_stays` et `soldes` sont injectables : l'écran « à affecter » traite
    # vingt-cinq lignes d'un coup, et chaque instance recalculait sinon le solde
    # des 351 séjours ouverts — une seconde par ligne, vingt-sept par page. Le
    # calcul est le même pour toutes : il se fait une fois, en amont.
    def initialize(cash_entry:, open_stays: nil, soldes: nil)
      @entry = cash_entry
      @stays_precharges = open_stays
      @soldes = soldes
    end

    def run
      catch_error(context: { cash_entry: @entry.id }) { match }
    end

    def run!
      match
    end

    private

    def match
      return nil unless @entry.incoming?

      # Une ambiguïté ne fait pas qu'échouer : elle DIT que l'imputation est
      # douteuse. Retomber sur un indice plus faible après ça reviendrait à
      # ignorer l'avertissement qu'on vient de recevoir. Vaut à tous les
      # niveaux, pas seulement pour la communication.
      [method(:by_communication), method(:by_known_iban),
       method(:by_counterparty_name), method(:by_exact_amount)].each do |niveau|
        resultat = niveau.call
        return nil if resultat == :ambiguous
        return resultat if resultat
      end

      nil
    end

    # 1 — la communication nomme le séjour. C'est une preuve, pas un indice.
    def by_communication
      texte = @entry.communication.to_s
      return nil if texte.blank?

      jetons = texte.scan(/\b[A-Za-z0-9_-]{16,}\b/)
      # Le dièse est OBLIGATOIRE. Sans lui, « SEJOUR 12 AU 15 AOUT » — une
      # communication parfaitement banale — se lit « séjour n°12 » et attribue
      # le virement à un séjour au hasard. Constaté sur les données réelles dès
      # le premier essai : c'est le genre d'erreur qui ne se voit jamais, parce
      # que le montant est juste et que seul le client est faux.
      numeros = texte.scan(/s[ée]jour\s*#\s*(\d+)/i).flatten

      candidats = (Stay.where(token: jetons).to_a + Stay.where(id: numeros).to_a).uniq

      # Une communication qui nomme DEUX séjours est ambiguë, pas informative.
      # Prendre le premier serait choisir au hasard entre deux clients.
      return :ambiguous if candidats.size > 1
      return nil if candidats.empty?

      stay = candidats.first
      # Le même filtre que les autres niveaux : un vieux numéro traînant dans une
      # communication ne doit pas rattacher un virement à un séjour déjà soldé.
      return nil unless OPEN_STATUSES.include?(stay.payment_status)

      Match.new(stay: stay, confidence: 95,
                rationale: "La communication nomme le séjour ##{stay.id}.")
    end

    # 2 — l'IBAN est connu pour un client. Il n'est connu que parce qu'un humain
    # l'a validé une fois : c'est de l'apprentissage, pas de la devinette.
    def by_known_iban
      clients = CustomerBankAccount.customers_for(@entry.counterparty_iban)
      return nil if clients.empty?

      # Un IBAN connu pour deux clients — un compte joint, une association et
      # son trésorier — ne désigne personne. On s'abstient plutôt que de choisir.
      return :ambiguous if clients.size > 1

      customer = clients.first

      candidats = open_stays.select { |stay| stay.customer_id == customer.id }
      return :ambiguous if candidats.size > 1
      return nil if candidats.empty?

      Match.new(stay: candidats.first, confidence: 85,
                rationale: "L'IBAN #{@entry.counterparty_iban} est connu pour #{customer_label(customer)}, " \
                           "qui a un séjour au solde ouvert.")
    end

    # 3 — le nom du tiers correspond à un client. Plus faible : deux familles
    # peuvent porter le même nom.
    def by_counterparty_name
      nom = @entry.counterparty_name.to_s.strip
      return nil if nom.length < 4

      candidats = open_stays.select do |stay|
        client = stay.customer
        next false if client.nil?

        [client.last_name, client.organization_name].compact.any? do |valeur|
          valeur.present? && nom.downcase.include?(valeur.downcase)
        end
      end
      return :ambiguous if candidats.size > 1
      return nil if candidats.empty?

      Match.new(stay: candidats.first, confidence: 60,
                rationale: "Le nom du tiers « #{nom} » correspond au client du séjour " \
                           "##{candidats.first.id}, au solde ouvert.")
    end

    # 4 — le montant tombe juste sur un seul séjour ouvert. Le plus faible des
    # quatre : c'est une coïncidence probable, pas une preuve.
    # Le SOLDE restant, pas le total facturé : un séjour partiellement réglé ne
    # doit pas se voir proposer un second virement du montant complet.
    def by_exact_amount
      montant = @entry.amount_cents.abs
      candidats = open_stays.select { |stay| remaining_cents(stay) == montant }
      return :ambiguous if candidats.size > 1
      return nil if candidats.empty?

      Match.new(stay: candidats.first, confidence: 45,
                rationale: "Le montant correspond exactement au solde restant du séjour " \
                           "##{candidats.first.id}, seul séjour ouvert à ce solde.")
    end

    # Le solde CANONIQUE du modèle, pas un calcul refait ici : `Stay` agrège les
    # paiements des deux canaux (lien direct et lien historique par booking) et
    # sait ce qui est réellement exigible. Recalculer à côté, c'est se
    # désynchroniser au premier changement de règle.
    # Le solde d'un séjour coûte deux requêtes. Il ne sert qu'au quatrième
    # niveau de la cascade — le plus faible, souvent jamais atteint. Le cache est
    # donc PARESSEUX et PARTAGÉ : rien n'est calculé tant qu'aucune ligne de la
    # page ne descend jusque-là, et une fois calculé le solde sert à toutes.
    def remaining_cents(stay)
      return stay.balance_due_cents.to_i if @soldes.nil?

      @soldes[stay.id] ||= stay.balance_due_cents.to_i
    end

    def open_stays
      @open_stays ||= begin
        fenetre = (@entry.entry_date - 1.year)..(@entry.entry_date + 6.months)
        if @stays_precharges
          # Le lot préchargé couvre l'union des fenêtres de la page ; chaque
          # ligne garde la sienne, filtrée en mémoire.
          @stays_precharges.select { |stay| fenetre.cover?(stay.departure_date) }
        else
          Stay.where(payment_status: OPEN_STATUSES).where(departure_date: fenetre)
              .includes(:customer).to_a
        end
      end
    end

    # Le lot des séjours ouverts couvrant une liste de lignes, et leurs soldes,
    # calculés UNE fois. À passer à chaque `MatchStay` de la même page.
    def self.prechargement(cash_entries)
      dates = cash_entries.map(&:entry_date)
      return [[], {}] if dates.empty?

      stays = Stay.where(payment_status: OPEN_STATUSES)
                  .where(departure_date: (dates.min - 1.year)..(dates.max + 6.months))
                  .includes(:customer).to_a
      # Le cache des soldes part VIDE : il se remplit à la demande, et seulement
      # si la cascade descend jusqu'au niveau qui en a besoin.
      [stays, {}]
    end

    def customer_label(customer)
      [customer.organization_name.presence,
       [customer.first_name, customer.last_name].compact.join(" ").presence].compact.first || "ce client"
    end
  end
end
