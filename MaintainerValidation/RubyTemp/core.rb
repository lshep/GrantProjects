require 'yaml'
require 'json'
require 'sqlite3'
require 'bcrypt'
require 'securerandom'
require 'aws-sdk'
require 'date'
require 'open-uri'

class CoreConfig
  @@request_uri  = nil
  @@db = nil
  @@auth_config = nil
  def self.set_request_uri(request_uri)
    @@request_uri = request_uri
  end
  def self.request_uri
    @@request_uri
  end
  def self.set_db(db)
    @@db = db
  end
  def self.db
    @@db
  end
  def self.set_auth_config(auth_config)
    @@auth_config = auth_config
  end
  def self.auth_config
    @@auth_config
  end
end

module Core

  CoreConfig.set_auth_config(YAML::load_file(File.join(File.dirname(__FILE__), "auth.yml" )))

  dbfile = File.join(File.dirname(__FILE__), "db.sqlite3" )
  CoreConfig.set_db(SQLite3::Database.new dbfile)
  if (!File.exists? dbfile) or (File.size(dbfile) == 0)
    rows = CoreConfig.db.execute <<-SQL.unindent
      create table maintainers (
        id integer primary key,
        package varchar(255) not null,
        name varchar(255) not null,
        email varchar(255) not null,
        consent_date date,
        pw_hash varchar(255),
        email_status varchar(255),
        is_email_valid boolean
      );
    SQL
  end

  
  def Core.handle_post(request)   ## TODO: Work in progress
    
    if CoreConfig.request_uri.nil?
      CoreConfig.set_request_uri(request.base_url)
    end
    if Core.is_spoof? request
      puts "Unknown IP address"
      return [400, "Unknown IP address"]
    end
    begin
      json = request.body.read
      obj = JSON.parse json
    rescue JSON::ParserError
      return [400, "Failed to parse JSON"]
    end
    if obj.has_key? 'action' and  obj['action'] == "newentry"
      return Core.handle_new_entries(obj)
    end
    if obj.has_key? 'action' and  obj['action'] == "verification"
      return Core.handle_verify_email(obj)
    end
    
  end
    
  def Core.handle_new_entries(obj)
    ## TODO: loop over all new entries?
    Core.add_entry_to_db(package, name, email)
    return "new entry added"
  end

  def Core.add_entry_to_db(package, name, email)
    consent_date = Date.today.to_s
    CoreConfig.db.execute "insert into maintainers (package, name, email, consent_date, email_status, is_email_valid) values (?,?,?,?,?,?)",
                          package, name, email, consent_date, "valid", true
  end

  def Core.handle_verify_email(obj)

    password = SecureRandom.hex(20)
    hash = BCrypt::Password.create(password)
    ## TODO:  add hash to database
    return Core.email_validation_request(name, email, password)
      
  end
  
  def Core.email_validation_request(name, email, password)
    recipient_email = email
    recipient_name = name
    from_email = "bioc-validation-noreply@bioconductor.org"
    from_name = "Bioconductor Core Team"
    msg = <<-END.unindent
      Hi #{name},
      
      This email is assoicated with at least one Bioconductor package.
      Bioconductor periodically will confirm valid maintainer emails and
      remind maintainers of Bioconductor policies and expectations. Failure to
      accept bioconductor policies by clicking the link below may result in
      package deprecation and removal. 

      Please review the Bioconductor:

        1. Code of Conduct: https://bioconductor.org/about/code-of-conduct/
        2. Maintainer Expectations: https://contributions.bioconductor.org/bioconductor-package-submissions.html#author
        3. Deprecation Practices: https://contributions.bioconductor.org/package-end-of-life-policy.html
            

      Accept Bioconductor Policies: #{CoreConfig.request_uri}/acceptpolicies/#{email}/accept/#{password}
 
      Please don't reply to this email.

      Thank you,

      The Bioconductor Core Team.
    END
    Core.send_email("#{from_name} <#{from_email}>",
      "#{recipient_name} <#{recipient_email}>",
      "Action required: Please Verify Bioconductor Policies",
      msg)
  end


  
  def Core.send_email(from, to, subject, message)
    aws = CoreConfig.auth_config['aws']
    ses = Aws::SES::Client.new(
      region: aws['region'],
      access_key_id: aws['aws_access_key_id'],
      secret_access_key: aws['aws_secret_access_key']
    )
    ses.send_email({
      source: from, # required
      destination: { # required
        to_addresses: [to]
      },
      message: { # required
        subject: { # required
          data: subject, # required
          charset: "UTF-8",
        },
        body: { # required
          text: {
            data: message, # required
            charset: "UTF-8",
          }
        },
      }
    })
  end


  def Core.get_entries_by_email(email)
    results_as_hash = CoreConfig.db.results_as_hash
    begin
      CoreConfig.db.results_as_hash = true
      rows = CoreConfig.db.execute("select * from maintainers where email = ?",
                                   email)
      return nil if rows.empty?
      return rows ## NOTE: Does this work right? 
    ensure
      CoreConfig.db.results_as_hash = results_as_hash
    end
  end


  def Core.accept_policies(email, action, password)
    
    entries = Core.get_entries_by_email(email)
    correct_password = BCrypt::Password.new(repos['pw_hash']) # FIX ME: might have multiple rows
    unless correct_password == password
      return "wrong password, you are not authorized"
    end

    ## TODO
    ## update datebase with valid email and new consent date
    consent_date = Date.today.to_s

  end

  
end
