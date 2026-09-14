# Dépôt-vente (epic #248). Pas de scheduler dans l'application : la demande
# mensuelle se lance à la main, et en dry-run par défaut — envoyer des emails
# par accident, à des gens qui ne sont pas de la maison, ne se rattrape pas.
namespace :consignment do
  desc "Crée le relevé du mois pour chaque artisan actif et envoie le lien. MONTH=YYYY-MM, APPLY=1 pour écrire"
  task request: :environment do
    # `force_encoding` : selon la locale du shell, une valeur d'ENV revient en
    # binaire, et le message d'erreur ci-dessous explose au lieu de s'afficher.
    raw = ENV["MONTH"].presence&.dup&.force_encoding(Encoding::UTF_8)
    if raw && raw !~ /\A\d{4}-\d{2}\z/
      abort "[consignment:request] MONTH doit s'écrire YYYY-MM (reçu : #{raw})."
    end

    month = begin
      raw ? Date.parse("#{raw}-01") : Date.current.prev_month.beginning_of_month
    rescue Date::Error
      abort "[consignment:request] MONTH doit s'écrire YYYY-MM (reçu : #{raw})."
    end

    apply = ENV["APPLY"].present?
    result = Consignments::Request.new(month: month, dry_run: !apply, resend: ENV["RESEND"].present?).run

    puts "[consignment:request] #{I18n.l(month, format: '%B %Y')} — #{result}"
    { "relevés" => result.created, "emails" => result.mailed, "écartés" => result.skipped }.each do |title, rows|
      next if rows.empty?

      puts "  #{title} :"
      rows.each { |row| puts "    - #{row}" }
    end
    puts "[consignment:request] Rien n'a été écrit — relance avec APPLY=1." unless apply
  end
end
