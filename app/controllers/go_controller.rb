class GoController < ApplicationController
	skip_before_filter :verify_authenticity_token, only: [:add_checked_id, :get_checked_ids, :remove_checked_id, :test]
	before_filter :is_search
	skip_before_filter :is_signed_in #, only: [:redirect]

	def is_search
		if params[:q] and request.path != '/go'
			redirect_to controller:'go', action:'index', q: params[:q]
		end
	end

	def redirect
		where = GoLink.handle_redirect(params[:key], myEmail)
		if where.length == 1
			golink = where.first
			Thread.new{
				golink.log_click(myEmail)
				ActiveRecord::Base.connection.close
			}
			# TODO remove reminders
			reminder_emails = Rails.cache.read('reminder_emails')
			if reminder_emails != nil and reminder_emails.include?(myEmail)
				redirect_to '/reminders?key='+golink.key
			else
				redirect_to golink.url
			end
		elsif where.length > 0
			@golinks = where
			@golinks = @golinks.paginate(:page => params[:page], :per_page => GoLink.per_page)
			@groups = Group.groups_by_email(myEmail)
			render :new_index
		else
			redirect_to '/go?q='+params[:key]
		end
	end

	def get_checked_ids
		render json: GoLink.get_checked_ids(myEmail)
	end


	def add_checked_id
		ids = GoLink.add_checked_id(myEmail, params[:id])
		render json: ids
	end

	def remove_checked_id
		ids = GoLink.remove_checked_id(myEmail, params[:id])
		render json: ids
	end

	def checked_links
		@golinks = GoLink.where('id in (?)', GoLink.get_checked_ids(myEmail))
		@golinks = @golinks.paginate(:page => params[:page], :per_page => GoLink.per_page)
		@groups = Group.groups_by_email(myEmail)
		@batch_editing = true
		@group = Group.new(name: 'Batch Edit Links')
		render :new_index
	end

	def deselect_links
		GoLink.deselect_links(myEmail)
		redirect_to "/go/menu"
	end

	def index
		if params[:group_id]
			@group = Group.find(params[:group_id])
			@group_editing = true
			viewable = GoLink.viewable_ids(myEmail)
			@ajax_params = '?group_id='+params[:group_id].to_s
			@golinks = @group.go_links.order('created_at desc').where('go_links.id in (?)', viewable)
		elsif params[:q]
			if params[:q].include?('http://') or params[:q].include?('https://')
				redirected = true
				redirect_to controller: 'go', action: 'add', url: params[:q]
			end
			@ajax_params = '?query='+params[:q].to_s
			@search_term = params[:q]
			@golinks = GoLink.email_search(params[:q], myEmail)
		else
			@golinks = GoLink.list(myEmail)
		end
		@groups = Group.groups_by_email(myEmail)
		
		@page = params[:page] ? params[:page].to_i : 1
		@golinks = @golinks.paginate(:page => params[:page], :per_page => GoLink.per_page)
		@golinks = @golinks.includes(:groups)
		if not redirected
			render :new_index
		end
	end

	def ajax_scroll
		if params[:query]
			@golinks = GoLink.email_search(params[:query], myEmail)
		elsif params[:group_id]
			@group = Group.find(params[:group_id])
			viewable = GoLink.viewable_ids(myEmail)
			@golinks = @group.go_links.order('created_at desc').where('go_links.id in (?)', viewable)
		else
			@golinks = GoLink.list(myEmail)
		end
		
		@golinks = @golinks.paginate(:page => params[:page], :per_page => GoLink.per_page)
		@golinks = @golinks.includes(:groups)
		if @golinks.length == 0
			render nothing: true, status: 404
		else
			render 'go/ajax', layout: false
		end
	end

	def show
		@golink = GoLink.find(params[:id])
		@groups = Group.groups_by_email(myEmail)
		render layout: false
	end


	def delete_checked
		GoLink.checked_golinks(myEmail).destroy_all
		GoLink.deselect_links(myEmail)
		redirect_to '/go'
	end


	def recent
		@recent = GoLinkClick.order('created_at DESC')
			.where.not(member_email: 'davidbliu@gmail.com')
			.first(1000)
		@email_hash = Member.email_hash
	end

	def admin
		@keys = GoLinkClick.all.pluck(:key).uniq
		@groups = Member.groups
	end


	def add
		if params[:key]
			@golinks = GoLink.where(key: params[:key]).map{|x| x.to_json}
		else
			@golinks = []
		end
		@groups = Group.groups_by_email(myEmail)
		@golink = GoLink.create(
			key: params[:key],
			url: params[:url],
			description: params[:desc],
			member_email: myEmail,
		)
	end

	def lookup
		render json: GoLink.url_matches(params[:url]).map{|x| x.to_json}
	end

	def search
		golinks = GoLink.email_search(params[:q], email)
		render json: golinks.map{|x| x.to_json}
	end



	def update
		golink = GoLink.find(params[:id])
		if params[:title]
			golink.title = params[:title].strip
		end
		if params[:key]
			golink.key = params[:key].strip
		end
		if params[:url]
			golink.url = params[:url].strip
		end
		if params[:description]
			golink.description = params[:description].strip
		end
		params[:groups] ||= []
		golink.groups = Group.where('id in (?)', params[:groups])
		golink.save!
		render json: golink.to_json
	end

	def destroy
		GoLink.find(params[:id]).destroy
		render nothing: true, status: 200
	end

 

	def batch_delete
		ids = JSON.parse(params[:ids])
		ids.each do |id|
			GoLink.find(id).destroy
		end
		begin
			redirect_to :back
		rescue ActionController::RedirectBackError
			redirect_to '/go/menu'
		end
	end

	def batch_update_groups
		add_groups = Group.where('id in (?)', params[:add])
		remove_groups = Group.where('id in (?)', params[:remove])
		remove_ids = remove_groups.pluck(:id)
		GoLink.checked_golinks(myEmail).each do |golink|
			golink.groups += add_groups
			golink.groups = golink.groups.select{|x| remove_ids.exclude?(x.id)}
			golink.groups = golink.groups.uniq
		end
		render nothing: true, status: 200
	end
	
#
# TODO: create reporting controller and move everything below to it
#

	def engagement
		keys = params[:keys] ? params[:keys].split(',') : []
		@keys = keys
		clicks = GoLinkClick.order('created_at DESC')
				.where.not(member_email:'davidbliu@gmail.com')
		if keys != []
			clicks = clicks.where('key in (?)', keys)
		end
		if params[:time] and params[:time] != ''
			time = Time.parse(params[:time])
			@time = time
			clicks = clicks.where('created_at > ?', time)
		end
		if params[:group] and params[:group] != ''
			@members = Member.get_group(params[:group]).order(:committee)
		else
			@members = Member.current_members
				.where.not(committee:'GM')
				.where.not(email:'davidbliu@gmail.com')
				.order(:committee)
		end

		@click_hash = {}
		seen = []
		@members.each do |m|
			@click_hash[m.email] = []
			seen << m.email
		end
		clicks.each do |click|
			if not seen.include?(click.member_email)
				@click_hash[click.member_email] = []
				seen << click.member_email
			else
				@click_hash[click.member_email] << click
			end
		end  

		@inactive = []
		@active = []
		@members.each do |m|
			if not @click_hash[m.email] or @click_hash[m.email].length ==0
				@inactive << m
			else
				@active << m
			end
		end
	end

	 def time_distribution
		@clicks = GoLinkClick.all
		@bins = Array.new(24, 0)
		@hours = (0..24).to_a
		@num = 0
		@clicks.each do |click|
			hour = click.created_at.in_time_zone("Pacific Time (US & Canada)").hour
			@bins[hour] = @bins[hour]+1
		end
		@golinks = GoLink.where(semester: Semester.current_semester)
		@num_clicks = @golinks.map{|x| x.get_num_clicks}
		@max = @num_clicks.max 
		@min = @num_clicks.min
		@avg = @num_clicks.mean
		@std = @num_clicks.standard_deviation
		@click_bins = Array.new(15, 0)
	end
end

module Enumerable
	def sum
		self.inject(0){|accum, i| accum + i }
	end

	def mean
		self.sum/self.length.to_f
	end

	def sample_variance
		m = self.mean
		sum = self.inject(0){|accum, i| accum +(i-m)**2 }
		sum/(self.length - 1).to_f
	end

	def standard_deviation
		return Math.sqrt(self.sample_variance)
	end
end 