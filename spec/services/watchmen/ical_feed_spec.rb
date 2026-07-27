require "rails_helper"

# issue #142 — flux iCal des gardes, abonnable depuis Google Agenda.
RSpec.describe Watchmen::IcalFeed do
  let!(:role) { Role.find_or_create_by!(id: described_class::WATCHMAN_ROLE_ID) { |r| r.name = "Veilleur·euse" } }

  def human(name)
    Human.create!(name: name)
  end

  def garde(human, date, status: :selected)
    HumanRole.create!(human: human, role: role, date: date, status: status)
  end

  # Le flux est plié à 75 octets (RFC 5545) : on déplie avant d'inspecter, sinon
  # une longue `DESCRIPTION` casserait les assertions.
  def unfolded(ics = subject.to_ics)
    ics.gsub("\r\n ", "")
  end

  def vevents(ics = subject.to_ics)
    unfolded(ics).scan(/BEGIN:VEVENT.*?END:VEVENT/m)
  end

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[CACHE SCHEMA TRANSACTION]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  describe "en-tête du calendrier" do
    it "porte PRODID, VERSION, CALSCALE et un X-WR-CALNAME lisible" do
      ics = unfolded

      expect(ics).to include("BEGIN:VCALENDAR")
      expect(ics).to include("VERSION:2.0")
      expect(ics).to include("CALSCALE:GREGORIAN")
      expect(ics).to include("PRODID:-//Les 4 Sources//Claudy Gardes//FR")
      expect(ics).to include("X-WR-CALNAME:Gardes — Les 4 Sources")
      expect(ics).to end_with("END:VCALENDAR\r\n")
    end

    it "termine TOUTES ses lignes par CRLF, comme l'exige la RFC" do
      garde(human("Ana"), Date.new(2026, 8, 12))

      ics = subject.to_ics

      expect(ics).not_to match(/(?<!\r)\n/)
      expect(ics.split("\r\n")).to all(satisfy { |line| line.bytesize <= 75 })
    end
  end

  describe "un événement par jour" do
    it "rend un VEVENT avec le nom de la personne de garde" do
      garde(human("Ana"), Date.new(2026, 8, 12))

      events = vevents

      expect(events.size).to eq(1)
      expect(events.first).to include("SUMMARY:Garde : Ana")
    end

    it "regroupe plusieurs personnes du même jour dans UN SEUL événement, noms triés" do
      date = Date.new(2026, 8, 12)
      garde(human("Bruno"), date)
      garde(human("Ana"), date)

      events = vevents

      expect(events.size).to eq(1)
      expect(events.first).to include("SUMMARY:Garde : Ana & Bruno")
    end

    it "trie les noms sans se laisser piéger par les accents" do
      date = Date.new(2026, 8, 12)
      garde(human("Fred"), date)
      garde(human("Émile"), date)

      expect(vevents.first).to include("SUMMARY:Garde : Émile & Fred")
    end

    it "rend les jours dans l'ordre chronologique" do
      ana = human("Ana")
      garde(ana, Date.new(2026, 8, 20))
      garde(ana, Date.new(2026, 8, 12))

      expect(subject.days.map(&:date)).to eq([Date.new(2026, 8, 12), Date.new(2026, 8, 20)])
    end

    it "ignore les backup : un backup seul sur une date ne produit AUCUN événement" do
      garde(human("Suppléante"), Date.new(2026, 8, 12), status: :backup)

      expect(vevents).to be_empty
    end

    it "n'exporte que les titulaires d'un jour mixte titulaire + backup" do
      date = Date.new(2026, 8, 12)
      garde(human("Ana"), date)
      garde(human("Suppléant"), date, status: :backup)

      events = vevents

      expect(events.size).to eq(1)
      expect(events.first).to include("SUMMARY:Garde : Ana")
      expect(events.first).not_to include("Suppléant")
    end
  end

  describe "événement all-day" do
    it "pose un DTSTART date et un DTEND au LENDEMAIN (borne exclusive iCal)" do
      garde(human("Ana"), Date.new(2026, 8, 12))

      event = vevents.first

      expect(event).to include("DTSTART;VALUE=DATE:20260812")
      expect(event).to include("DTEND;VALUE=DATE:20260813")
    end

    it "passe correctement une fin de mois" do
      garde(human("Ana"), Date.new(2026, 8, 31))

      event = vevents.first

      expect(event).to include("DTSTART;VALUE=DATE:20260831")
      expect(event).to include("DTEND;VALUE=DATE:20260901")
    end
  end

  describe "UID stable" do
    it "dérive l'UID de la date, à l'identique entre deux générations" do
      garde(human("Ana"), Date.new(2026, 8, 12))

      first = described_class.new.to_ics
      second = described_class.new.to_ics

      expect(unfolded(first)).to include("UID:garde-20260812@claudy.les4sources.be")
      expect(first).to eq(second)
    end

    it "garde le même UID quand la composition du jour change (mise à jour, pas doublon)" do
      date = Date.new(2026, 8, 12)
      garde(human("Ana"), date)
      before_ics = described_class.new.to_ics

      garde(human("Bruno"), date)
      after_ics = described_class.new.to_ics

      expect(unfolded(after_ics)).to include("UID:garde-20260812@claudy.les4sources.be")
      expect(vevents(after_ics).size).to eq(1)
      expect(unfolded(before_ics)).to include("SUMMARY:Garde : Ana")
      expect(unfolded(after_ics)).to include("SUMMARY:Garde : Ana & Bruno")
    end

    it "porte un DTSTAMP UTC" do
      garde(human("Ana"), Date.new(2026, 8, 12))

      expect(vevents.first).to match(/DTSTAMP:\d{8}T\d{6}Z/)
    end
  end

  describe "lien vers le calendrier Claudy du mois" do
    it "pointe vers le 1er du mois de la garde, en URL et en DESCRIPTION" do
      garde(human("Ana"), Date.new(2026, 8, 12))

      event = vevents.first

      expect(event).to include("URL:http://localhost:3000/?date=2026-08-01")
      expect(event).to include("Calendrier Claudy : http://localhost:3000/?date=2026-08-01")
    end

    it "construit l'hôte depuis la configuration de l'app, pas en dur" do
      garde(human("Ana"), Date.new(2026, 8, 12))

      allow(Rails.application.config.action_mailer)
        .to receive(:default_url_options).and_return(host: "app.les4sources.be")

      expect(vevents.first).to include("URL:http://app.les4sources.be/?date=2026-08-01")
    end

    it "refuse de générer un flux si aucun hôte n'est configuré" do
      garde(human("Ana"), Date.new(2026, 8, 12))

      allow(Rails.application.config.action_mailer).to receive(:default_url_options).and_return({})

      expect { subject.to_ics }.to raise_error(described_class::MissingHostError)
    end
  end

  describe "échappement RFC 5545" do
    it "échappe virgule et point-virgule dans un nom sans casser le flux" do
      garde(human("Dupont, Ana; dite Nana"), Date.new(2026, 8, 12))

      event = vevents.first

      expect(event).to include('SUMMARY:Garde : Dupont\, Ana\; dite Nana')
      expect(vevents.size).to eq(1)
    end

    it "échappe l'antislash une seule fois" do
      garde(human('Ana \\ Bruno'), Date.new(2026, 8, 12))

      expect(vevents.first).to include('SUMMARY:Garde : Ana \\\\ Bruno')
    end

    it "rend la DESCRIPTION multi-ligne avec un \\n littéral, pas un vrai saut de ligne" do
      garde(human("Ana"), Date.new(2026, 8, 12))

      description = unfolded[/^DESCRIPTION:.*$/]

      expect(description).to include('Garde : Ana\nCalendrier Claudy :')
    end
  end

  describe "pliage des lignes longues" do
    it "plie à 75 octets et se déplie sans perte" do
      # Assez de noms pour dépasser largement 75 octets sur le SUMMARY.
      date = Date.new(2026, 8, 12)
      %w[Anastasia Bartholomew Clementine Dieudonné Ermengarde].each { |n| garde(human(n), date) }

      ics = subject.to_ics
      expected = "SUMMARY:Garde : Anastasia & Bartholomew & Clementine & Dieudonné & Ermengarde"

      expect(ics).not_to include(expected)              # la ligne brute est pliée
      expect(unfolded(ics)).to include(expected)        # dépliée, elle est intacte
      expect(ics.split("\r\n")).to all(satisfy { |line| line.bytesize <= 75 })
    end

    it "ne coupe jamais un caractère multi-octets en deux" do
      date = Date.new(2026, 8, 12)
      6.times { |i| garde(human("Éléonore#{i}Ç"), date) }

      ics = subject.to_ics

      expect(ics.valid_encoding?).to be(true)
      expect(unfolded(ics)).to include("Éléonore0Ç & Éléonore1Ç")
    end
  end

  describe "membres devenus inactifs" do
    # `Human` porte un `default_scope` (status "active" + soft-deletion) : un
    # `includes(:human)` viderait le titre de ces journées historiques.
    it "conserve le nom d'un membre passé inactif" do
      ancienne = human("Claire")
      garde(ancienne, Date.new(2024, 3, 4))
      ancienne.update_columns(status: "inactive")

      expect(vevents.first).to include("SUMMARY:Garde : Claire")
    end

    it "conserve le nom d'un membre soft-deleted" do
      partie = human("Zoé")
      garde(partie, Date.new(2024, 3, 4))
      partie.update_columns(deleted_at: Time.current)

      expect(vevents.first).to include("SUMMARY:Garde : Zoé")
    end
  end

  describe "performance" do
    it "ne fait aucun N+1 : le nombre de requêtes ne dépend pas du nombre de jours" do
      ana = human("Ana")
      bruno = human("Bruno")

      garde(ana, Date.new(2026, 8, 1))
      garde(bruno, Date.new(2026, 8, 1))
      few = count_queries { described_class.new.to_ics }

      (2..30).each do |day|
        garde(ana, Date.new(2026, 8, day))
        garde(bruno, Date.new(2026, 8, day))
      end
      many = count_queries { described_class.new.to_ics }

      expect(described_class.new.days.size).to eq(30)
      expect(many).to eq(few)
      expect(many).to be <= 2
    end
  end

  describe "couverture" do
    it "couvre tout l'historique, sans fenêtre glissante" do
      ana = human("Ana")
      garde(ana, Date.new(2023, 11, 9))
      garde(ana, Date.today)
      garde(ana, Date.new(2026, 8, 30))

      expect(vevents.size).to eq(3)
      expect(unfolded).to include("DTSTART;VALUE=DATE:20231109")
      expect(unfolded).to include("DTSTART;VALUE=DATE:20260830")
    end

    it "ne rend aucun VEVENT quand il n'y a aucune garde" do
      expect(vevents).to be_empty
      expect(unfolded).to include("BEGIN:VCALENDAR")
    end
  end
end
