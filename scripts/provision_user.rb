# Run inside the web container via `bin/rails runner -`, invoked by
# scripts/create-user.sh. Not meant to be run standalone.
#
# Uses the "free" plan, not "trial": User#with_params (app/models/user.rb),
# which backs the web signup form, already picks "free" over "trial" whenever
# ENV["STRIPE_API_KEY"] is unset -- exactly this deployment's case -- because
# "trial" has an expires_at that TrialExpiration (run periodically by the
# clock container) enforces by setting suspended=true, and once suspended,
# SiteController#check_user locks the account out of the web UI with no way
# to pay since Stripe isn't configured. "free" has no expiry and is never
# touched by that job. Also repairs users whose plan_id ended up nil
# (Plans table wasn't seeded yet when they registered) or is still "trial"
# (created before this script picked "free").
email    = ENV.fetch("PROVISION_EMAIL")
password = ENV.fetch("PROVISION_PASSWORD")
make_admin = ENV["PROVISION_ADMIN"] == "true"

# db:prepare only seeds on the run that creates the database from scratch;
# rebuilds against an already-initialized volume can skip it, leaving the
# Plans table empty. Seed if needed instead of assuming it happened.
Rails.application.load_seed if Plan.count.zero?

free = Plan.find_by(stripe_id: "free")
raise "free plan still missing after seeding db/seeds.rb" unless free

user = User.find_by(email: email)

if user
  puts "User #{email} already exists (id=#{user.id})."
  # update_columns bypasses validations/callbacks on purpose: plan_type_valid
  # (on: :update) checks the plan's price_tier against the user's price_tier,
  # which only matters for Stripe billing tiers this self-hosted setup
  # doesn't use, and would reject re-attaching a plan this way otherwise.
  updates = {}
  updates[:plan_id] = free.id if user.plan.nil? || user.plan.stripe_id == "trial"
  updates[:expires_at] = nil if user.expires_at
  updates[:suspended] = false if user.suspended?
  updates[:admin] = true if make_admin && !user.admin?
  if updates.any?
    user.update_columns(updates)
    puts "Repaired: #{updates}"
  else
    puts "Nothing to repair (plan=#{user.plan&.stripe_id.inspect}, admin=#{user.admin?})."
  end
else
  user = User.new(email: email, password: password, password_confirmation: password)
  user.plan = free
  user.free_ok = true
  user.expires_at = nil
  user.admin = true if make_admin
  user.save!
  puts "Created user #{email} (id=#{user.id})."
end

user.reload
puts "id=#{user.id} email=#{user.email} admin=#{user.admin?} plan=#{user.plan&.stripe_id.inspect}"
