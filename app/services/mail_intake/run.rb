module MailIntake
  # Un passage complet : rapatrier chaque boîte active, puis analyser ce qui
  # ne l'a pas encore été (messagerie, phase 1). Une boîte en panne n'empêche
  # pas les autres ; un mail que Jev n'a pas pu lire sera repris au passage
  # suivant, puisqu'il reste sans `analyzed_at`.
  class Run
    def initialize(jev: Jev::Client.new)
      @jev = jev
    end

    def run!
      report = []
      MailAccount.actives.find_each do |account|
        created = Sync.new(mail_account: account).run!
        report << "#{account.address} : #{created.size} nouveau(x)"
      rescue StandardError => e
        Sentry.capture_exception(e) unless e.is_a?(Sync::MissingPassword)
        report << "#{account.address} : ÉCHEC — #{e.message}"
      end

      analyzed = 0
      MailMessage.to_analyze.find_each do |message|
        Analyze.new(mail_message: message, jev: @jev).run!
        analyzed += 1
      rescue StandardError => e
        Sentry.capture_exception(e)
        report << "mail ##{message.id} : analyse en échec — #{e.message}"
      end
      report << "#{analyzed} mail(s) analysé(s)"
      report
    end
  end
end
