module Finance
  # Le guide de la comptabilité (Michael, 2026-10-17) : ce qu'il faut à une
  # personne qui DÉMARRE pour oser ouvrir la section.
  #
  # Les écrans sont justes, mais ils parlent le langage de celle qui les a
  # demandés : « affecter », « rapprocher », « contre-passer », « À-nouveau ».
  # Quelqu'un qui arrive ne sait ni par où commencer, ni ce que veut dire le
  # bouton qu'il a sous les yeux. D'où trois choses, toutes tirées d'ici :
  #
  #   * un LEXIQUE en mots simples, une seule fois, pour que la même notion ne
  #     soit pas expliquée de trois façons sur trois écrans ;
  #   * une AIDE PAR ÉCRAN (à quoi il sert, les gestes dans l'ordre, les mots à
  #     connaître), posée par le layout sous le titre de chaque page ;
  #   * la ROUTINE : ce qu'on fait chaque semaine, chaque mois, chaque année.
  #
  # Le texte vit en Ruby et non dans les vues : une spec vérifie que chaque
  # écran de la section a son aide, et que chaque mot cité existe au lexique.
  module Guide
    Term = Data.define(:key, :word, :definition)
    Page = Data.define(:purpose, :steps, :terms)
    # Un geste de la routine : son libellé et la route qui y mène.
    Task = Data.define(:label, :route)

    TERMS = [
      Term.new("a-affecter", "À affecter",
               "L'état d'une ligne de trésorerie dont personne n'a encore dit ce qu'elle est. Le compteur « À affecter » " \
               "doit tomber à zéro chaque mois : tant qu'il ne l'est pas, aucun résultat n'est fiable."),
      Term.new("a-nouveau", "À-nouveau",
               "L'écriture du premier jour d'un exercice, qui reprend les soldes de la fin de l'exercice précédent " \
               "(banque, dettes, prêts…). Sans elle, chaque année repartirait de zéro."),
      Term.new("affecter", "Affecter",
               "Dire à quoi correspond un mouvement d'argent : quel compte du plan comptable (par exemple un achat de " \
               "marchandises), quelle entité et, si possible, quel pôle. Une ligne peut être affectée en plusieurs parts."),
      Term.new("analytique", "Analytique (pôle)",
               "La deuxième lecture des chiffres : non plus par nature (achats, loyers…) mais par activité (hébergement, " \
               "épicerie, bar…). C'est le pôle qu'on choisit en affectant. Ce qui n'a pas de pôle reste visible comme " \
               "« non affecté »."),
      Term.new("arrete", "Arrêté du mois",
               "Le contrôle de fin de mois. Claudy vérifie que tout est importé, affecté, facturé et envoyé, puis on " \
               "fige le mois. Il se fait au début du mois suivant."),
      Term.new("balance", "Balance",
               "Le tableau de tous les comptes avec leur total au débit, au crédit et leur solde sur une période. Le " \
               "total des débits égale toujours celui des crédits : sinon, quelque chose cloche."),
      Term.new("charge-fixe", "Charge fixe",
               "Une dépense qui revient (abonnement, assurance, emprunt), notée une fois pour que la trésorerie la " \
               "prévoie. Ce n'est pas une dette, c'est une prévision. À ne pas confondre avec les charges récurrentes, " \
               "qui facturent les habitants (section Comptes)."),
      Term.new("coda", "CODA",
               "Le format des relevés bancaires belges. On le télécharge dans la banque en ligne et on le dépose dans " \
               "Claudy : chaque mouvement devient une ligne de trésorerie. Beobank donne un fichier Excel à la place, " \
               "qui se dépose au même endroit."),
      Term.new("comptabiliser", "Comptabiliser",
               "Transformer une ligne entièrement affectée en écriture au grand livre (on dit aussi « passer » " \
               "l'écriture). Avant, tout se corrige ; après, on ne corrige plus qu'en contre-passant."),
      Term.new("compte", "Compte du plan comptable",
               "Un numéro à six chiffres qui range chaque montant par nature. Le premier chiffre donne la famille : " \
               "1 fonds propres et prêts, 2 bâtiments et matériel, 4 tiers (40 clients, 44 fournisseurs), 5 banque et " \
               "caisse, 6 charges (ce qu'on dépense), 7 produits (ce qu'on gagne)."),
      Term.new("compte-courant", "Compte courant d'un habitant",
               "Le compte de chaque ménage ou Sourcier : ce qu'il consomme (bar, charges) et ce qu'il paie. Il se lit " \
               "dans la section Comptes ; en comptabilité, on y rapproche les virements des habitants."),
      Term.new("contre-passer", "Contre-passer",
               "Annuler une écriture en passant l'écriture inverse, du même montant. Une écriture ne s'efface jamais : " \
               "l'erreur et sa correction restent lisibles."),
      Term.new("debit-credit", "Débit et crédit",
               "Les deux colonnes de toute écriture. Pour la banque, un débit est de l'argent qui entre et un crédit de " \
               "l'argent qui sort. Chaque écriture a autant au débit qu'au crédit : c'est la « partie double ». Claudy " \
               "les génère, tu n'as jamais à les taper."),
      Term.new("decompte", "Décompte",
               "Le relevé mensuel du compte courant d'un habitant : ce qu'il doit et ce qu'il a payé. Il s'émet puis " \
               "s'envoie, depuis la section Comptes."),
      Term.new("dette", "Dette ou litige",
               "Une somme que la maison doit, ou risque de devoir, sans facture encodée : une taxe réclamée, un arriéré, " \
               "une contestation. On la note pour que la trésorerie ne paraisse pas meilleure qu'elle n'est."),
      Term.new("echeance", "Échéance",
               "Une date légale à tenir : déclaration de TVA, dépôt des comptes, impôts. Chaque obligation (la règle) " \
               "produit ses échéances (les dates)."),
      Term.new("ecriture", "Écriture",
               "Une ligne datée du grand livre qui dit qu'un montant passe d'un compte à un autre. Elle naît d'un fait " \
               "(ligne de banque, facture, décompte), jamais d'une saisie à la main."),
      Term.new("entite", "Entité",
               "Une structure juridique qui tient sa propre comptabilité, comme la Fondation ou la SRL. Une dépense de " \
               "l'une payée depuis le compte de l'autre reste une dépense de la première."),
      Term.new("exclure", "Exclure",
               "Sortir de la file une ligne de trésorerie qui n'a rien à y faire (un doublon, par exemple). Elle ne se " \
               "supprime pas : on donne un motif, et la trace reste."),
      Term.new("exercice", "Exercice",
               "L'année comptable d'une entité. Une fois l'exercice clôturé, plus aucune écriture n'y bouge."),
      Term.new("facture-achat", "Facture d'achat",
               "Une facture reçue d'un fournisseur. Elle passe par « À traiter » (on complète ses lignes), « À valider » " \
               "(le pôle dit oui), « À payer », puis « Payée » quand le virement est rapproché."),
      Term.new("facture-vente", "Facture de vente",
               "Une facture que la maison émet (dans OkiOki). Claudy la garde, la relie à ce qu'elle facture et dit si " \
               "elle est payée."),
      Term.new("grand-livre", "Grand livre",
               "Toutes les écritures d'un compte, dans l'ordre, avec le solde qui court. C'est là qu'on répond à " \
               "« d'où vient ce chiffre ? »."),
      Term.new("note-de-frais", "Note de frais, note de mission",
               "Une dépense avancée par quelqu'un pour la maison (avec ses tickets), ou des kilomètres parcourus pour " \
               "elle (note de mission). On l'encode, on la traite, puis on la rembourse."),
      Term.new("pret", "Prêt reçu",
               "De l'argent prêté à la maison (comptes 17). Il gonfle la banque mais doit être rendu : ce n'est pas de " \
               "la marge."),
      Term.new("rapprocher", "Rapprocher",
               "Relier une ligne de banque à ce qu'elle paie ou encaisse : une facture, une note de frais, un séjour, le " \
               "compte d'un habitant, un versement Stripe. Le compte se déduit de la pièce : c'est plus sûr que " \
               "d'affecter à la main, et la dette se solde du même geste."),
      Term.new("regle", "Règle d'affectation",
               "Une consigne du type « si la communication contient Voo, propose tel compte ». Elle propose, elle ne " \
               "décide jamais : c'est toi qui acceptes ou refuses."),
      Term.new("releve", "Relevé de reversement",
               "Le document qui dit ce qu'on doit reverser à quelqu'un : un porteur d'activité, un artisan du " \
               "dépôt-vente, un partenaire d'hébergement. On le génère en brouillon, on le relit, puis on l'émet."),
      Term.new("solde-verifie", "Solde vérifié",
               "Le solde d'un compte en banque tel que le dernier relevé importé le donne. C'est le point de départ de " \
               "« Peut-on dépenser ? »."),
      Term.new("stripe", "Stripe et versement",
               "Stripe encaisse les paiements par carte, puis vire leur total sur la banque, commissions déduites : " \
               "c'est le versement. Une seule ligne de banque cache donc plusieurs ventes et des frais, que Claudy " \
               "ventile."),
      Term.new("suggestion", "Suggestion",
               "Une proposition d'affectation, faite par une règle ou par Jev (l'assistant qui lit les mails et les " \
               "pièces). Elle prépare le geste ; il faut encore l'accepter."),
      Term.new("tiers", "Tiers",
               "Toute personne ou organisation avec qui la maison échange de l'argent : fournisseur, client, prêteur. " \
               "Son IBAN sert à la payer."),
      Term.new("tresorerie", "Ligne de trésorerie",
               "Un mouvement réel d'argent : une ligne du relevé bancaire, une entrée de caisse, une opération Stripe. " \
               "Toute la comptabilité part de là."),
      Term.new("ventiler", "Ventiler",
               "Répartir un même montant entre plusieurs comptes ou pôles. Par exemple, le paiement d'un séjour réparti " \
               "entre hébergement, repas et activités.")
    ].index_by(&:key).freeze

    # L'aide de chaque écran, par `controller_path`, ou `controller_path#action`
    # quand une action dit autre chose que sa liste (la file « À affecter », la
    # fiche d'une ligne). Trois gestes au plus : au-delà, c'est un mode d'emploi,
    # et il a sa place dans le guide.
    PAGES = {
      "finance/accounting" => Page.new(
        "La page d'accueil de la comptabilité : peut-on dépenser, ce qui attend d'être fait, et les chiffres qui " \
        "pèsent (dettes, prêts, échéances).",
        ["Commence par « À faire » : chaque ligne mène à la file qu'il faut vider, dans l'ordre du travail.",
         "Lis « Peut-on dépenser ? » avant toute dépense importante.",
         "Si un mot t'arrête, le guide (en haut à droite de la barre) l'explique."],
        %w[a-affecter solde-verifie pret dette]
      ),
      "finance/guide" => Page.new(
        "Le mode d'emploi de la section : comment l'argent circule dans Claudy, ta routine et le lexique.",
        [], []
      ),
      "finance/treasury" => Page.new(
        "Le détail de la trésorerie de la Fondation : ce qu'il y a en banque, ce qui doit rentrer, ce qui doit sortir.",
        ["Vérifie que le solde correspond à la banque en ligne : sinon, un relevé manque (Banque & caisse › CODA).",
         "Parcours ce qui doit sortir : chaque montant a sa liste, cliquable."],
        %w[solde-verifie charge-fixe dette]
      ),
      "finance/general_accounts" => Page.new(
        "Le plan comptable : la liste numérotée des comptes dans lesquels on range chaque montant.",
        ["Cherche un compte par son numéro ou son nom avant d'en créer un : il existe presque toujours.",
         "Ne modifie un compte qu'avec l'accord du comptable : c'est son plan."],
        %w[compte]
      ),
      "finance/legal_entities" => Page.new(
        "Les structures juridiques qui tiennent chacune leur comptabilité, et leurs comptes en banque.",
        ["Vérifie que chaque compte en banque a son IBAN : sans lui, l'import des relevés ne le reconnaît pas."],
        %w[entite]
      ),
      "finance/fiscal_years" => Page.new(
        "Les exercices comptables de chaque entité, ouverts ou clôturés.",
        ["Un exercice se clôture une fois le bilan arrêté avec le comptable, jamais avant."],
        %w[exercice a-nouveau]
      ),
      "finance/cash_entries" => Page.new(
        "Le journal de trésorerie : tous les mouvements d'argent réels (banque, caisse, Stripe), un par ligne.",
        ["Cherche une ligne par un nom ou un mot de la communication.",
         "Pour faire le travail, ouvre « À affecter » : c'est la file qui doit tomber à zéro."],
        %w[tresorerie a-affecter]
      ),
      "finance/cash_entries#unallocated" => Page.new(
        "La file des mouvements qu'il reste à expliquer. Ton travail : la vider, ligne par ligne ou par lots.",
        ["Si une suggestion est proposée et juste, accepte-la.",
         "Sinon, rapproche la ligne de ce qu'elle paie (facture, note de frais, séjour, habitant) : c'est le geste le " \
         "plus sûr.",
         "S'il n'y a rien à rapprocher, affecte-la à un compte et à un pôle. En cas de doute, laisse un commentaire " \
         "et passe à la suivante."],
        %w[affecter rapprocher suggestion ventiler]
      ),
      "finance/cash_entries#show" => Page.new(
        "La fiche d'une ligne de trésorerie : d'où elle vient, à quoi elle est affectée, et son écriture.",
        ["Complète l'affectation jusqu'à couvrir tout le montant.",
         "Clique alors « Comptabiliser cette ligne ». Pour corriger après, clique « Modifier la ventilation » : " \
         "l'écriture est contre-passée, pas effacée.",
         "Si la ligne n'a rien à faire là, exclus-la avec un motif."],
        %w[affecter comptabiliser contre-passer exclure]
      ),
      "finance/cash_reallocations" => Page.new(
        "Corriger la ventilation d'une ligne déjà affectée, même comptabilisée : ses comptes, ses pôles, ses " \
        "entités et ses montants, en un seul geste.",
        ["Change ce qui doit l'être, ajoute ou retire une part, puis enregistre : tout passe ensemble, ou rien.",
         "Si la ligne était comptabilisée, son écriture est contre-passée et la nouvelle ventilation se " \
         "comptabilise dès qu'elle couvre tout le montant.",
         "Une part qui rapproche une pièce (facture, séjour, note de frais) la garde. La retirer défait ce " \
         "rapprochement."],
        %w[ventiler contre-passer rapprocher]
      ),
      "finance/monthly_close" => Page.new(
        "La liste de contrôle du mois : tout ce qui doit être fait pour que le mois soit fini, calculé depuis les " \
        "données.",
        ["Ouvre-la au début du mois, sur le mois précédent.",
         "Traite les points dans l'ordre : chacun a son bouton qui mène au bon écran.",
         "Quand tout est vert, arrête le mois."],
        %w[arrete coda a-affecter decompte]
      ),
      "finance/compliance_deadlines" => Page.new(
        "L'échéancier : les dates légales à tenir (TVA, comptes annuels, impôts), en retard d'abord.",
        ["Commence par ce qui est en retard, puis les 30 prochains jours.",
         "Ouvre une échéance pour la démarrer, puis la clôturer quand c'est fait."],
        %w[echeance]
      ),
      "finance/compliance_obligations" => Page.new(
        "Les règles de l'échéancier : chaque obligation produit ses échéances, mois après mois ou année après année.",
        ["Vérifie qu'une obligation n'existe pas déjà avant d'en créer une.",
         "Une obligation ne se supprime pas : désactive-la si elle ne s'applique plus."],
        %w[echeance]
      ),
      "finance/coda_imports" => Page.new(
        "Le dépôt des relevés bancaires : chaque fichier ajoute ses mouvements à la trésorerie.",
        ["Télécharge le relevé dans la banque en ligne (CODA chez Triodos, Excel chez Beobank).",
         "Dépose-le ici. Redéposer un fichier déjà importé ne crée rien : pas de doublon à craindre.",
         "Les nouvelles lignes attendent ensuite dans « À affecter »."],
        %w[coda tresorerie a-affecter]
      ),
      "finance/allocation_rules" => Page.new(
        "Les règles qui proposent une affectation quand une ligne revient souvent (Voo, l'assurance, le bar…).",
        ["Crée une règle quand tu affectes plusieurs fois la même chose à la main.",
         "Regarde ses compteurs d'acceptations et de refus : une règle souvent refusée est à corriger."],
        %w[regle suggestion]
      ),
      "finance/cash_sheet" => Page.new(
        "La feuille de caisse du mois : chaque entrée ou sortie d'espèces, avec un motif.",
        ["Note chaque mouvement d'espèces avec son motif : le motif suffit à l'affecter.",
         "Compte la caisse chaque semaine pour repérer un écart pendant qu'on s'en souvient."],
        %w[tresorerie affecter]
      ),
      "finance/cash_motifs" => Page.new(
        "Les motifs de la feuille de caisse, et le compte auquel chacun affecte.",
        ["Range les motifs du plus fréquent au plus rare : c'est l'ordre de la liste de saisie.",
         "Un motif ne se supprime pas : désactive-le."],
        %w[affecter compte]
      ),
      "finance/cash_counts" => Page.new(
        "Les comptages de caisse : billet par billet, la caisse dit si elle est juste.",
        ["Compte la caisse chaque semaine, en vingt secondes.",
         "Un écart se cherche tout de suite : sur sept jours on s'en souvient, sur trente plus personne."],
        %w[]
      ),
      "finance/stripe" => Page.new(
        "Les comptes Stripe (paiements par carte) et le compte où va chaque catégorie de ventes.",
        ["Vérifie la date du dernier import de chaque compte.",
         "Donne une correspondance à chaque nouvelle catégorie de ventes, sinon ses lignes restent à affecter."],
        %w[stripe ventiler]
      ),
      "finance/stripe_category_mappings" => Page.new(
        "Une correspondance : le compte et le pôle qui reçoivent une catégorie de ventes Stripe.",
        [], %w[stripe compte analytique]
      ),
      "finance/collection_cost" => Page.new(
        "Ce que coûte le fait d'être payé : les commissions Stripe, en euros et en pourcentage.",
        ["Dépose chaque mois le justificatif des frais Stripe."],
        %w[stripe]
      ),
      "finance/mail_messages" => Page.new(
        "Les mails arrivés sur l'adresse de la comptabilité, avec ce que Jev propose d'en faire.",
        ["Ouvre chaque mail : si c'est une facture, le bouton de création prépare la facture d'achat à partir " \
         "de la pièce.",
         "Sinon, ignore-le. Un mail ne sort de la file que par l'un de ces deux gestes."],
        %w[facture-achat suggestion]
      ),
      "finance/purchase_invoices" => Page.new(
        "Les factures reçues des fournisseurs, et où chacune en est.",
        ["Complète les factures « À traiter » : fournisseur, lignes, comptes, jusqu'à couvrir le total.",
         "Celles « À valider » attendent le oui d'un pôle ; celles « À payer » sont dans la file À payer."],
        %w[facture-achat tiers compte]
      ),
      "finance/payables" => Page.new(
        "Tout ce que la maison doit virer, toutes dettes confondues, par échéance.",
        ["Fais les virements dans la banque en ligne, avec la communication indiquée.",
         "Au prochain relevé, rapproche chaque virement de sa dette dans « À affecter » : elle passe alors payée."],
        %w[rapprocher facture-achat note-de-frais]
      ),
      "finance/liabilities" => Page.new(
        "Ce que la maison doit ou risque de devoir sans facture : une taxe réclamée, un arriéré, un litige.",
        ["Note le montant réclamé et ce que tu retiens, en restant prudent (le haut de la fourchette).",
         "Mets à jour quand la facture arrive ou que le litige se règle."],
        %w[dette]
      ),
      "finance/recurring_expenses" => Page.new(
        "Les charges fixes : ce que la maison paie à intervalle régulier, pour que la trésorerie le prévoie.",
        ["Ajoute une charge dès qu'un nouvel abonnement, prélèvement ou remboursement d'emprunt commence.",
         "Supprime-la quand il s'arrête."],
        %w[charge-fixe]
      ),
      "finance/third_parties" => Page.new(
        "Les tiers : fournisseurs, clients et prêteurs, avec leur IBAN.",
        ["Cherche avant de créer : un doublon éparpille les factures d'un même fournisseur.",
         "Un tiers ne se supprime pas : désactive-le."],
        %w[tiers]
      ),
      "finance/sales_invoices" => Page.new(
        "Les factures émises dans OkiOki : ce qu'elles facturent et si elles sont payées.",
        ["Une facture s'enregistre depuis ce qu'elle facture, sur la page Accueil › Facturation, avec son " \
         "numéro OkiOki.",
         "Son paiement se rapproche depuis « À affecter »."],
        %w[facture-vente rapprocher]
      ),
      "finance/expense_reports" => Page.new(
        "Les notes de frais et de mission : ce qu'une personne a avancé pour la maison, ou les kilomètres parcourus.",
        ["Encode la note avec ses lignes et, pour chaque ticket, sa photo ou la mention « fourni sur papier ». Pas de compte à choisir à ce stade.",
         "Un ticket papier reçoit un numéro : écris-le dessus, puis dépose les tickets dans le bac « Admin », attachés, dans la farde plastique à ton nom.",
         "Passe-la en traitement depuis sa fiche : attribue le compte de charge et le pôle de chaque ligne, elle reçoit son numéro et rejoint la file À payer.",
         "Rembourse, puis rapproche le virement."],
        %w[note-de-frais rapprocher]
      ),
      "finance/carrier_statements" => Page.new(
        "Les relevés de rémunération des porteurs d'activité.",
        ["Génère le relevé en brouillon et relis-le.",
         "Émets-le : il est alors figé, comptabilisé et envoyé au porteur, et rejoint la file À payer."],
        %w[releve]
      ),
      "finance/consignment_reports" => Page.new(
        "Le dépôt-vente : chaque mois, ce que les artisans ont vendu et ce qu'on leur doit.",
        ["Regarde qui a déclaré et qui reste muet ; relance si besoin.",
         "Vérifie le relevé, puis règle-le par virement ou en liant la facture de l'artisan."],
        %w[releve]
      ),
      "finance/revenue_share_agreements" => Page.new(
        "Les accords de partage des revenus d'un hébergement, et leurs relevés.",
        ["Génère le relevé de la période en brouillon, relis-le, puis émets-le."],
        %w[releve]
      ),
      "finance/revenue_share_statements" => Page.new(
        "Un relevé de partage de revenus : ce qu'on reverse au partenaire pour une période.",
        ["Relis le brouillon avant de l'émettre : un relevé émis ne se modifie plus."],
        %w[releve contre-passer]
      ),
      "finance/ledger" => Page.new(
        "Le grand livre : toutes les écritures d'un compte, avec le solde qui court.",
        ["Choisis un compte et une période pour retrouver d'où vient un chiffre.",
         "Chaque écriture mène à la pièce ou à la ligne qui l'a produite."],
        %w[grand-livre ecriture debit-credit]
      ),
      "finance/trial_balance" => Page.new(
        "La balance : le total de chaque compte sur une période. Débits et crédits doivent être égaux.",
        ["Si les totaux ne sont pas égaux, signale-le : c'est une erreur à corriger."],
        %w[balance debit-credit compte]
      ),
      "finance/analytic_balance" => Page.new(
        "Ce que chaque pôle rapporte et coûte, sur une période.",
        ["Regarde la part « non affecté » : plus elle est grande, moins les chiffres des pôles sont fiables."],
        %w[analytique]
      ),
      "finance/budgets" => Page.new(
        "Le budget d'une année, entité par entité : une ligne par pôle et par compte, face au réel de référence.",
        ["Tant que rien n'est enregistré, chaque case propose le réel des 12 derniers mois : corrige ce qui va changer, puis enregistre.",
         "Vide une case pour retirer la ligne ; « Ajouter une ligne » pour un compte qui n'a pas bougé.",
         "Le résultat prévu se recalcule pendant la saisie. S'il est négatif, le budget prévoit un déficit."],
        %w[analytique compte entite]
      ),
      "finance/cross_check" => Page.new(
        "Le contrôle croisé du mois : l'argent encaissé en regard de ce que les séjours ont facturé.",
        ["Un écart n'est pas une erreur : c'est ce qui reste à encaisser plus ce qui reste à affecter."],
        %w[a-affecter]
      )
    }.freeze

    # La routine de la personne qui tient la comptabilité, de la plus fréquente
    # à la plus rare. Les gestes renvoient aux écrans ; le détail vit dans
    # l'aide de chacun.
    ROUTINE = [
      ["Chaque semaine", [
        Task.new("Vider la boite de réception : chaque facture reçue devient une facture d'achat", :finance_mail_messages_path),
        Task.new("Importer les relevés bancaires", :finance_coda_imports_path),
        Task.new("Affecter ou rapprocher les nouvelles lignes", :finance_unallocated_cash_entries_path),
        Task.new("Faire les virements de la file À payer", :finance_payables_path),
        Task.new("Compter la caisse", :new_finance_cash_count_path)
      ]],
      ["Au début de chaque mois", [
        Task.new("Ouvrir l'arrêté du mois précédent et suivre ses étapes", :finance_monthly_close_path),
        Task.new("Émettre les relevés des porteurs d'activité", :finance_carrier_statements_path),
        Task.new("Vérifier et régler le dépôt-vente", :finance_consignment_reports_path),
        Task.new("Regarder l'échéancier : ce qui tombe dans le mois", :finance_compliance_deadlines_path)
      ]],
      ["Chaque année", [
        Task.new("Préparer le bilan avec le comptable : grand livre et balance", :finance_trial_balance_path),
        Task.new("Clôturer l'exercice, puis ouvrir le suivant", :finance_fiscal_years_path)
      ]]
    ].freeze

    # Le circuit de l'argent, en cinq temps : l'idée à comprendre avant tout le
    # reste, c'est que tout part d'un mouvement réel.
    CIRCUIT = [
      ["Un mouvement d'argent entre", "Le relevé de banque, la caisse ou Stripe apporte une ligne de trésorerie."],
      ["Tu dis ce qu'il est", "Tu le rapproches de ce qu'il paie, ou tu l'affectes à un compte et à un pôle."],
      ["Claudy écrit la comptabilité", "La ligne se comptabilise : débit et crédit se génèrent tout seuls."],
      ["Les états se remplissent", "Grand livre, balance et analytique lisent ces écritures."],
      ["Le mois se ferme", "L'arrêté vérifie que rien n'a été oublié, puis fige le mois."]
    ].freeze

    def self.terms = TERMS.values.sort_by { |term| I18n.transliterate(term.word).downcase }

    def self.term(key) = TERMS.fetch(key)

    # L'aide d'une action précise d'abord, celle de l'écran ensuite.
    def self.page(controller_path, action_name)
      PAGES["#{controller_path}##{action_name}"] || PAGES[controller_path]
    end
  end
end
