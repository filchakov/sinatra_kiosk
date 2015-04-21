require 'rubygems'
require 'sinatra'
require 'active_record'
require 'digest/md5'

require "./smsc_api"

ActiveRecord::Base.establish_connection(
  :adapter  => "mysql2",
  :host     => "127.0.0.1",
  :username => "root",
  :password => "",
  :database => "sinatra"
)

@type = 'json'

class User < ActiveRecord::Base
	has_one :cart
	has_one :login
end
class Cart < ActiveRecord::Base
	belongs_to :user
end

class Client < ActiveRecord::Base
	has_one :terminal
end
class Terminal < ActiveRecord::Base
	belongs_to :client
	has_one :login
end
class Login < ActiveRecord::Base
	belongs_to :client
	belongs_to :terminal
	belongs_to :user
end

#добавить учет расхода за смс, по каждому терминалу

=begin
Генерируем код для авторизации
Входящие данные number (телефона), terminal (token)
=end
#curl -X POST -H "Content-type: application/x-www-form-urlencoded" "http://localhost:4567/login" -d 'number=380952488232&terminal=token_terminal'
post '/login' do
	return {:error => 1, :code => 1, :msg => 'not_number_or_terminal'}.to_json if params[:number].nil? || params[:terminal].nil?
	sms = SMSC.new()
	user = User.find_by_number(params[:number])
	user = User.create :number => params[:number], :date_create => Time.now.utc if user.nil?
	terminal = Terminal.find_by_token(params[:terminal])
	sms_rand = rand(100..999)
	sms.send_sms(user.number, "Ваш пароль: #{sms_rand}", 1)
	login = Login.create :user_id => user.id, :terminal => terminal, :session => Digest::MD5.hexdigest("#{user.number} #{Time.now.utc}"), :sms_code => sms_rand, :expiration_date => Time.now.utc + 5.minute
	login.to_json
end


#curl -X POST -H "Content-type: application/x-www-form-urlencoded" "http://localhost:4567/active_sms" -d 'sms_code=866&session=03455011529328e6aca83e3f9dc52ac3'
post '/active_sms' do
	login = Login.where("sms_code = ? AND session = ? AND expiration_date >= ? AND status != 1", params[:sms_code], params[:session], Time.now.utc)
	unless login.nil? || login.count !=1
		login.first.status = 1 
		login.first.expiration_date = Time.now.utc + 1.minute
		login.first.save
		return login.first.to_json
	else
		return {:error => 1, :code => 2, :msg => 'activete_sms'}.to_json
	end
end

#curl -X POST -H "Content-type: application/x-www-form-urlencoded" "http://localhost:4567/check_timeout" -d 'session=b0b967ff51456c060ed33dd243623350'
post '/check_timeout' do
	return check_timeout.to_json
end

post '/update_session' do
	update_session
end

def check_timeout
	return Login.where("session = ? AND status = 1 AND expiration_date >= ?", params[:session], Time.now.utc).count == 1
end

def update_session
	puts Time.now.utc
	if check_timeout
		session = Login.find_by_session(params[:session])
		unless session.nil?
			session.update_attributes(:expiration_date => Time.now.utc + 1.minute)
			session.save
		end
		return session.to_json
	end
	return {:error => 1, :code => 3, :msg => 'token_expiration_failed'}.to_json
end


#curl -X POST -H "Content-type: application/x-www-form-urlencoded" "http://localhost:4567/" -d 'name=curlname&fullname=curlfullname'
post '/' do
  var = User.create
  var.name = params[:name]
  var.fullname = params[:fullname]
	var.cart = Cart.new
  var.save
  return var.to_json
end