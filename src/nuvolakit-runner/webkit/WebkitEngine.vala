/*
 * Copyright 2014-2017 Jiří Janoušek <janousek.jiri@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met: 
 * 
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer. 
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

using Nuvola.JSTools;

namespace Nuvola
{

public class WebkitEngine : WebEngine
{
	private const string ZOOM_LEVEL_CONF = "webview.zoom_level";
	
	public override Gtk.Widget get_main_web_view(){return web_view;}
	private void set_web_plugins(bool enabled) {web_view.get_settings().enable_plugins = enabled;}
	
	private void set_media_source_extension (bool enabled){web_view.get_settings().enable_mediasource = enabled;}
	private bool get_media_source_extension(){return web_view.get_settings().enable_mediasource;}
	
	private AppRunnerController runner_app;
	private WebKit.WebContext web_context;
	private WebView web_view;
	private JsEnvironment? env = null;
	private JSApi api;
	private IpcBus ipc_bus = null;
	private Config config;
	private Drt.KeyValueStorage session;
	
	public WebkitEngine(WebkitOptions web_options){
		base(web_options);
		web_context = web_options.default_context;
		set_web_plugins(web_options.flash_required);
		set_media_source_extension(web_options.mse_required);
	}
	
	public override void early_init(AppRunnerController runner_app, IpcBus ipc_bus,
			WebApp web_app, Config config, Connection? connection, HashTable<string, Variant> worker_data)	{
		
		this.ipc_bus = ipc_bus;
		this.runner_app = runner_app;
		this.web_app = web_app;
		this.config = config;
		this.web_worker = new RemoteWebWorker(ipc_bus);
		
		worker_data["NUVOLA_API_ROUTER_TOKEN"] = ipc_bus.router.hex_token;
		worker_data["WEBKITGTK_MAJOR"] = WebKit.get_major_version();
		worker_data["WEBKITGTK_MINOR"] = WebKit.get_minor_version();
		worker_data["WEBKITGTK_MICRO"] = WebKit.get_micro_version();
		worker_data["LIBSOUP_MAJOR"] = Soup.get_major_version();
		worker_data["LIBSOUP_MINOR"] = Soup.get_minor_version();
		worker_data["LIBSOUP_MICRO"] = Soup.get_micro_version();
		
		if (connection != null)
			apply_network_proxy(connection);	
		
		var webkit_extension_dir = Nuvola.get_libdir();
		debug("Nuvola WebKit Extension directory: %s", webkit_extension_dir);
		web_context.set_web_extensions_directory(webkit_extension_dir);
		var web_extension_data = Drt.variant_from_hashtable(worker_data);
		debug("Nuvola WebKit Extension data: %s", web_extension_data.print(true));
		web_context.set_web_extensions_initialization_user_data(web_extension_data);
		
		if (web_app.allow_insecure_content)
			web_context.get_security_manager().register_uri_scheme_as_secure("http");
		
		web_context.download_started.connect(on_download_started);
		
		web_view = new WebView(web_context);
		config.set_default_value(ZOOM_LEVEL_CONF, 1.0);
		web_view.zoom_level = config.get_double(ZOOM_LEVEL_CONF);
		web_view.load_changed.connect(on_load_changed);
		web_view.notify["is-loading"].connect_after(on_is_loading_changed);
		web_view.get_back_forward_list().changed.connect_after(on_back_forward_list_changed);
		session = new Drt.KeyValueMap();
		register_ipc_handlers();
	}
	
	~WebkitEngine()
	{
		web_view.get_back_forward_list().changed.disconnect(on_back_forward_list_changed);
	}
	
	public signal void webkit_context_menu(WebKit.ContextMenu menu, Gdk.Event event, WebKit.HitTestResult hit_test_result);
	
	
	public override void init()
	{
		web_view.load_html("<html><body>A web app will be loaded shortly...</body></html>", WEB_ENGINE_LOADING_URI);
	}
	
	public override void init_app_runner()
	{
		if (!ready)
		{
			web_view.notify["uri"].connect(on_uri_changed);
			web_view.notify["zoom-level"].connect(on_zoom_level_changed);
			web_view.decide_policy.connect(on_decide_policy);
			web_view.script_dialog.connect(on_script_dialog);
			web_view.context_menu.connect(on_context_menu);
		
			env = new JsRuntime();
			uint[] webkit_version = {WebKit.get_major_version(), WebKit.get_minor_version(), WebKit.get_micro_version()};
			uint[] libsoup_version = {Soup.get_major_version(), Soup.get_minor_version(), Soup.get_micro_version()};
			api = new JSApi(
				runner_app.storage, web_app.data_dir, storage.config_dir, config, session, webkit_version,
				libsoup_version, false);
			api.call_ipc_method_void.connect(on_call_ipc_method_void);
			api.call_ipc_method_sync.connect(on_call_ipc_method_sync);
			api.call_ipc_method_async.connect(on_call_ipc_method_async);
			try
			{
				api.inject(env);
				api.initialize(env);
			}
			catch (JSError e)
			{
				runner_app.fatal_error("Initialization error", e.message);
			}
			try
			{
				var args = new Variant("(s)", "InitAppRunner");
				env.call_function_sync("Nuvola.core.emit", ref args);
			}
			catch (GLib.Error e)
			{
				runner_app.fatal_error("Initialization error",
					"%s failed to initialize app runner. Initialization exited with error:\n\n%s".printf(
					runner_app.app_name, e.message));
			}
			debug("App Runner Initialized");
			ready = true;
		}
		if (!request_init_form())
		{
			debug("App Runner Ready");
			app_runner_ready();
		}
	}
	
	private bool web_worker_initialized_cb()
	{
		if (!web_worker.initialized)
		{
			web_worker.initialized = true;
			debug("Init finished");
			init_finished();
		}
		debug("Web Worker Ready");
		web_worker_ready();
		return false;
	}
	
	public override void load_app()
	{
		can_go_back = web_view.can_go_back();
		can_go_forward = web_view.can_go_forward();
		try
		{
			var url = env.send_data_request_string("LastPageRequest", "url");
			if (url != null)
			{
				if (load_uri(url))
					return;
				runner_app.show_error("Invalid page URL", "The web app integration script has not provided a valid page URL '%s'.".printf(url));
			}
		}
		catch (GLib.Error e)
		{
			runner_app.show_error("Initialization error", "%s failed to retrieve a last visited page from previous session. Initialization exited with error:\n\n%s".printf(runner_app.app_name, e.message));
		}
		
		go_home();
	}
	
	public override void go_home()
	{
		try
		{
			var url = env.send_data_request_string("HomePageRequest", "url");
			if (url == null)
				runner_app.fatal_error("Invalid home page URL", "The web app integration script has provided an empty home page URL.");
			else if (!load_uri(url))
			{
				runner_app.fatal_error("Invalid home page URL", "The web app integration script has not provided a valid home page URL '%s'.".printf(url));
			}
		}
		catch (GLib.Error e)
		{
			runner_app.fatal_error("Initialization error", "%s failed to retrieve a home page of  a web app. Initialization exited with error:\n\n%s".printf(runner_app.app_name, e.message));
		}
	}
	
	public override void apply_network_proxy(Connection connection)
	{
		WebKit.NetworkProxyMode proxy_mode;
		WebKit.NetworkProxySettings? proxy_settings = null;
		string? host;
		int port;
		var type = connection.get_network_proxy(out host, out port);
		switch (type)
		{
		case NetworkProxyType.SYSTEM:
			proxy_mode = WebKit.NetworkProxyMode.DEFAULT;
			break;
		case NetworkProxyType.DIRECT:
			proxy_mode = WebKit.NetworkProxyMode.NO_PROXY;
			break;
		default:
			proxy_mode = WebKit.NetworkProxyMode.CUSTOM;
			var proxy_uri = "%s://%s:%d/".printf(
				type == NetworkProxyType.HTTP ? "http" : "socks",
				(host != null && host != "") ? host : "127.0.0.1", port);
			proxy_settings = new WebKit.NetworkProxySettings(proxy_uri, null);
			break;
		}
		web_context.set_network_proxy_settings(proxy_mode, proxy_settings);
	}
	
	public override string? get_url() {
		return web_view != null ? web_view.uri : null;
	}
	
	public override void load_url(string url) {
		load_uri(url);
	}
	
	private bool load_uri(string uri)
	{
		if (uri.has_prefix("http://") || uri.has_prefix("https://"))
		{
			web_view.load_uri(uri);
			return true;
		}
		
		if (uri.has_prefix("nuvola://"))
		{
			web_view.load_uri(web_app.data_dir.get_child(uri.substring(9)).get_uri());
			return true;
		}
		
		if (uri.has_prefix(web_app.data_dir.get_uri()))
		{
			web_view.load_uri(uri);
			return true;
		}
		
		return false;
	}
	
	
	
	public override void go_back()
	{
		web_view.go_back();
	}
	
	public override void go_forward()
	{
		web_view.go_forward();
	}
	
	public override void reload()
	{
		web_view.reload();
	}
	
	public override void zoom_in()
	{
		web_view.zoom_in();
	}
	
	public override void zoom_out()
	{
		web_view.zoom_out();
	}
	
	public override void zoom_reset()
	{
		web_view.zoom_reset();
	}
	
	public override void set_user_agent(string? user_agent)
	{
		const string APPLE_WEBKIT_VERSION = "604.1";
		const string SAFARI_VERSION = "11.0";
		const string FIREFOX_VERSION = "52.0";
		const string CHROME_VERSION = "58.0.3029.81";
		string? agent = null;
		string? browser = null;
		string? version = null;	
		if (user_agent != null)
		{
			agent = user_agent.strip();
			if (agent[0] == '\0')
				agent = null;
		}
		
		if (agent != null)
		{
			var parts = agent.split_set(" \t", 2);
			browser = parts[0];
			if (browser != null)
			{
				browser = browser.strip();
				if (browser[0] == '\0')
					browser = null;
			}
			version = parts[1];
			if (version != null)
			{
				version = version.strip();
				if (version[0] == '\0')
					version = null;
			}
		}
		
		switch (browser)
		{
		case "CHROME":
			var s = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/%s Safari/537.36";
			agent = s.printf(version ?? CHROME_VERSION);
			break;
		case "FIREFOX":
			var s = "Mozilla/5.0 (X11; Linux x86_64; rv:%1$s) Gecko/20100101 Firefox/%1$s";
			agent = s.printf(version ?? FIREFOX_VERSION);
			break;
		case "SAFARI":
			var s = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_2) AppleWebKit/%1$s (KHTML, like Gecko) Version/%2$s Safari/%1$s";
			agent = s.printf(APPLE_WEBKIT_VERSION, version ?? SAFARI_VERSION);
			break;
		case "WEBKIT":
			var s = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/%1$s (KHTML, like Gecko) Version/%2$s Safari/%1$s";
			agent = s.printf(APPLE_WEBKIT_VERSION, version ?? SAFARI_VERSION);
			break;
		}
		
		unowned WebKit.Settings settings = web_view.get_settings();
		if (agent == null)
		{
			settings.enable_site_specific_quirks = true;
			settings.set_user_agent_with_application_details("Nuvola", Nuvola.get_short_version());
		}
		else
		{
			settings.enable_site_specific_quirks = false;
			settings.user_agent = agent + " Nuvola/" + Nuvola.get_short_version();
		}
		message("User agent set '%s'", settings.user_agent);
	}
	
	public override void get_preferences(out Variant values, out Variant entries)
	{
		var args = new Variant("(s@a{sv}@av)", "PreferencesForm", new Variant.array(new VariantType("{sv}"), {}), new Variant.array(VariantType.VARIANT, {}));
		try
		{
			env.call_function_sync("Nuvola.core.emit", ref args);
		}
		catch (GLib.Error e)
		{
			runner_app.show_error("Integration error", "%s failed to load preferences with error:\n\n%s".printf(runner_app.app_name, e.message));
		}
		args.get("(s@a{smv}@av)", null, out values, out entries);
	}

	public override void call_function_sync(string name, ref Variant? params, bool propagate_error=false) throws GLib.Error
	{
		env.call_function_sync(name, ref params);
	}
	
	private bool request_init_form()
	{
		Variant values;
		Variant entries;
		var args = new Variant("(s@a{sv}@av)", "InitializationForm", new Variant.array(new VariantType("{sv}"), {}), new Variant.array(VariantType.VARIANT, {}));
		try
		{
			env.call_function_sync("Nuvola.core.emit", ref args);
		}
		catch (GLib.Error e)
		{
			runner_app.fatal_error("Initialization error", "%s failed to crate initialization form. Initialization exited with error:\n\n%s".printf(runner_app.app_name, e.message));
			return false;
		}
		
		args.get("(s@a{smv}@av)", null, out values, out entries);
		var values_hashtable = Drt.variant_to_hashtable(values);
		if (values_hashtable.size() > 0)
		{
			debug("Init form requested");
			init_form(values_hashtable, entries);
			return true;
		}
		return false;
	}
	
	private void register_ipc_handlers() {
		assert(ipc_bus != null);
		var router = ipc_bus.router;
		router.add_method("/nuvola/core/web-worker-initialized", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE,
			"Notify that the web worker has been initialized.",
			handle_web_worker_initialized, null);
		router.add_method("/nuvola/core/web-worker-ready", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE,
			"Notify that the web worker is ready.",
			handle_web_worker_ready, null);
		router.add_method("/nuvola/core/get-data-dir", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.READABLE,
			"Return data directory.",
			handle_get_data_dir, null);
		router.add_method("/nuvola/core/get-user-config-dir", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.READABLE,
			"Return user config directory.",
			handle_get_user_config_dir, null);
		router.add_method("/nuvola/core/session-has-key", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.READABLE,
			"Whether the session has a given key.",
			handle_session_has_key, {
			new Drt.StringParam("key", true, false, null, "Session key.")
		});
		router.add_method("/nuvola/core/session-get-value", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.READABLE,
			"Get session value for the given key.",
			handle_session_get_value, {
			new Drt.StringParam("key", true, false, null, "Session key.")
		});
		router.add_method("/nuvola/core/session-set-value", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE,
			"Set session value for the given key.",
			handle_session_set_value, {
			new Drt.StringParam("key", true, false, null, "Session key."),
			new Drt.VariantParam("value", true, true, null, "Session value.")
		});
		router.add_method("/nuvola/core/session-set-default-value", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE,
			"Set default session value for the given key.",
			handle_session_set_default_value, {
			new Drt.StringParam("key", true, false, null, "Session key."),
			new Drt.VariantParam("value", true, true, null, "Session value.")
		});
		router.add_method("/nuvola/core/config-has-key", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.READABLE,
			"Whether the config has a given key.",
			handle_config_has_key, {
			new Drt.StringParam("key", true, false, null, "Config key.")
		});
		router.add_method("/nuvola/core/config-get-value", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.READABLE,
			"Get config value for the given key.",
			handle_config_get_value, {
			new Drt.StringParam("key", true, false, null, "Config key.")
		});
		router.add_method("/nuvola/core/config-set-value", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE,
			"Set config value for the given key.",
			handle_config_set_value, {
			new Drt.StringParam("key", true, false, null, "Config key."),
			new Drt.VariantParam("value", true, true, null, "Config value.")
		});
		router.add_method("/nuvola/core/config-set-default-value", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE,
			"Set default config value for the given key.",
			handle_config_set_default_value, {
			new Drt.StringParam("key", true, false, null, "Config key."),
			new Drt.VariantParam("value", true, true, null, "Config value.")
		});
		router.add_method("/nuvola/core/show-error", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE,
			"Show error message.",
			handle_show_error, {
			new Drt.StringParam("text", true, false, null, "Error message.")
		});
		router.add_method("/nuvola/browser/download-file-async", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE,
				"Download file.",
				handle_download_file_async, {
				new Drt.StringParam("uri", true, false, null, "File to download."),
				new Drt.StringParam("basename", true, false, null, "Basename of the file."),
				new Drt.DoubleParam("callback-id", true, null, "Callback id.")
			});
	}
	
	private void handle_web_worker_ready(Drt.RpcRequest request) throws Drt.RpcError {
		if (!web_worker.ready) {
			web_worker.ready = true;
			if (get_media_source_extension()) {
				Drt.EventLoop.add_idle(() => {
					var args = new Variant.tuple({});
					try {
						web_worker.call_function_sync("Nuvola.checkMSE", ref args, true);
					} catch (GLib.Error e) {
						runner_app.fatal_error("Initialization error", "Your distributor set the --webkitgtk-supports-mse build flag but your WebKitGTK+ library does not include Media Source Extension.\n\n" + e.message);
					}
					return false;
				});
			}
		}
		web_worker_ready();
		request.respond(null);
	}
	
	private void handle_web_worker_initialized(Drt.RpcRequest request) throws Drt.RpcError {
		var channel = request.connection as Drt.RpcChannel;
		return_val_if_fail(channel != null, null);
		ipc_bus.connect_web_worker(channel);
		Idle.add(web_worker_initialized_cb);
		request.respond(null);
	}
	
	private void handle_get_data_dir(Drt.RpcRequest request) throws Drt.RpcError {
		request.respond(new Variant.string(web_app.data_dir.get_path()));
	}
	
	private void handle_get_user_config_dir(Drt.RpcRequest request) throws Drt.RpcError {
		request.respond(new Variant.string(storage.config_dir.get_path()));
	}
	
	private void handle_session_has_key(Drt.RpcRequest request) throws Drt.RpcError {
		request.respond(new Variant.boolean(session.has_key(request.pop_string())));
	}
	
	private void handle_session_get_value(Drt.RpcRequest request) throws Drt.RpcError {
		var response = session.get_value(request.pop_string());
		if (response == null) {
			response = new Variant("mv", null);
		}
		request.respond(response);
	}
	
	private void handle_session_set_value(Drt.RpcRequest request) throws Drt.RpcError {
		session.set_value(request.pop_string(), request.pop_variant());
		request.respond(null);
	}
	
	private void handle_session_set_default_value(Drt.RpcRequest request) throws Drt.RpcError {
		session.set_default_value(request.pop_string(), request.pop_variant());
		request.respond(null);
	}
	
	private void handle_config_has_key(Drt.RpcRequest request) throws Drt.RpcError {
		request.respond(new Variant.boolean(config.has_key(request.pop_string())));
	}
	
	private void handle_config_get_value(Drt.RpcRequest request) throws Drt.RpcError {
		var response = config.get_value(request.pop_string());
		if (response == null) {
			response = new Variant("mv", null);
		}
		request.respond(response);
	}
	
	private void handle_config_set_value(Drt.RpcRequest request) throws Drt.RpcError {
		config.set_value(request.pop_string(), request.pop_variant());
		request.respond(null);
	}
	
	private void handle_config_set_default_value(Drt.RpcRequest request) throws Drt.RpcError {
		config.set_default_value(request.pop_string(), request.pop_variant());
		request.respond(null);
	}
	
	private void handle_show_error(Drt.RpcRequest request) throws Drt.RpcError 	{
		runner_app.show_error("Integration error", request.pop_string());
		request.respond(null);
	}
	
	private void on_call_ipc_method_void(string name, Variant? data) {
		try {
			ipc_bus.local.call.begin(name, data, (o, res) => {
				try {
					ipc_bus.local.call.end(res);	
				} catch (GLib.Error e) {
					warning("IPC call error: %s", e.message);
				}});
		} catch (GLib.Error e) {
			critical("Failed to send message '%s'. %s", name, e.message);
		}
	}
	
	private void on_call_ipc_method_async(JSApi js_api, string name, Variant? data, int id) {
		try {
			ipc_bus.local.call.begin(name, data, (o, res) => {
				try {
					var response = ipc_bus.local.call.end(res);
					js_api.send_async_response(id, response, null);
				} catch (GLib.Error e) {
					js_api.send_async_response(id, null, e);
				}});
		} catch (GLib.Error e) {
			critical("Failed to send message '%s'. %s", name, e.message);
		}
	}
	
	private void on_call_ipc_method_sync(string name, Variant? data, ref Variant? result) {
		try {
			result = ipc_bus.local.call_sync(name, data);
		} catch (GLib.Error e) {
			critical("Failed to send message '%s'. %s", name, e.message);
			result = null;
		}
	}
	
	private void handle_download_file_async(Drt.RpcRequest request) throws Drt.RpcError {
		var uri = request.pop_string();
		var basename = request.pop_string();
		var cb_id = request.pop_double();

		var dir = storage.cache_dir.get_child("api-downloads");
		try
		{
			dir.make_directory_with_parents();
		}
		catch (GLib.Error e)
		{
		}
		var file = dir.get_child(basename);
		try
		{
			file.@delete();
		}
		catch (GLib.Error e)
		{
		}
		var download = web_context.download_uri(uri);
		download.set_destination(file.get_uri());
		ulong[] handler_ids = new ulong[2];
		
		handler_ids[0] = download.finished.connect((d) => {
			try
			{
				var payload = new Variant(
					"(dbusss)", cb_id, true, d.get_response().status_code, d.get_response().status_code.to_string(), file.get_path(), file.get_uri());
				web_worker.call_function_sync("Nuvola.browser._downloadDone", ref payload);
			}
			catch (GLib.Error e)
			{
				warning("Communication failed: %s", e.message);
			}
			download.disconnect(handler_ids[0]);
			download.disconnect(handler_ids[1]);
			
		});
		
		handler_ids[1] = download.failed.connect((d, err) => {
			WebKit.DownloadError e = (WebKit.DownloadError) err;
			if (e is WebKit.DownloadError.DESTINATION)
				warning("Download failed because of destination: %s", e.message);
			else
				warning("Download failed: %s", e.message);
			try
			{
				var payload = new Variant(
					"(dbusss)", cb_id, false, d.get_response().status_code, d.get_response().status_code.to_string(), "", "");
				web_worker.call_function_sync("Nuvola.browser._downloadDone", ref payload);
			}
			catch (GLib.Error e)
			{
				warning("Communication failed: %s", e.message);
			}
			download.disconnect(handler_ids[0]);
			download.disconnect(handler_ids[1]);
		});
		
		request.respond(null);
	}
	
	private void on_load_changed(WebKit.LoadEvent load_event)
	{
		#if FLATPAK
		if (load_event == WebKit.LoadEvent.COMMITTED)
		{
			debug("Terminate WebKitPluginProcess2");
			/* https://github.com/tiliado/nuvolaruntime/issues/354 */
			Drt.System.sigall(Drt.System.find_pid_by_basename("WebKitPluginProcess2"), GLib.ProcessSignal.TERM);
		}
		#endif
		if (load_event == WebKit.LoadEvent.STARTED && web_worker != null)
		{
			debug("Load started");
			web_worker.ready = false;
		}
	}
	
	private void on_download_started(WebKit.Download download)
	{
		download.decide_destination.connect(on_download_decide_destination);
	}
	
	private bool on_download_decide_destination(WebKit.Download download, string filename)
	{
	
		if (download.destination == null)
			download.cancel();
		download.decide_destination.disconnect(on_download_decide_destination);
		return true;
	}
	
	private bool decide_navigation_policy(bool new_window, WebKit.NavigationPolicyDecision decision)
	{
		var action = decision.navigation_action;
		var uri = action.get_request().uri;
		if (!uri.has_prefix("http://") && !uri.has_prefix("https://"))
			return false;
		
		var handled = false;
		var load_uri = false;
		var new_window_override = new_window;
		var approved = navigation_request(uri, ref new_window_override);
		var javascript_enabled = true;
		const string KEEP_USER_AGENT = "KEEP_USER_AGENT";
		string? user_agent = KEEP_USER_AGENT;
		ask_page_settings(uri, new_window_override, ref javascript_enabled, ref user_agent);
		var web_settings = web_view.get_settings();
		
		var type = action.get_navigation_type();
		var user_gesture = action.is_user_gesture();
		debug("Navigation, %s window: uri = %s, approved = %s, frame = %s, type = %s, user gesture %s",
			new_window_override ? "new" : "current", uri, approved.to_string(), decision.frame_name, type.to_string(),
			user_gesture.to_string());
		
		// We care only about user clicks
		if (type == WebKit.NavigationType.LINK_CLICKED || user_gesture)
		{
			if (approved)
			{
				load_uri = handled = true;
				if (new_window != new_window_override)
				{
					if (!new_window_override)
					{
						// Open in current window instead of a new window
						load_uri = false;
						Idle.add(() => {web_view.load_uri(uri); return false;});
					}
					else
					{
						warning("Overriding of new window flag false -> true hasn't been implemented yet.");
					}
				}
			}
			else
			{
				runner_app.show_uri(uri);
				handled = true;
				load_uri = false;
			}
		}
		if (handled)
		{
			if (load_uri)
			{
				web_settings.enable_javascript = javascript_enabled;
				if (user_agent != KEEP_USER_AGENT)
					set_user_agent(user_agent);
				decision.use();
			}
			else
			{
				decision.ignore();
			}
		}
		return handled;
	}
	
	private bool on_decide_policy(WebKit.PolicyDecision decision, WebKit.PolicyDecisionType decision_type)
	{
		switch (decision_type)
		{
		case WebKit.PolicyDecisionType.NAVIGATION_ACTION:
			return decide_navigation_policy(false, (WebKit.NavigationPolicyDecision) decision);
		case WebKit.PolicyDecisionType.NEW_WINDOW_ACTION:
			return decide_navigation_policy(true, (WebKit.NavigationPolicyDecision) decision);
		case WebKit.PolicyDecisionType.RESPONSE:
		default:
			return false;
		}
	}
	
	private bool navigation_request(string url, ref bool new_window)
	{
		var builder = new VariantBuilder(new VariantType("a{smv}"));
		builder.add("{smv}", "url", new Variant.string(url));
		builder.add("{smv}", "approved", new Variant.boolean(true));
		builder.add("{smv}", "newWindow", new Variant.boolean(new_window));
		var args = new Variant("(s@a{smv})", "NavigationRequest", builder.end());
		try
		{
			env.call_function_sync("Nuvola.core.emit", ref args);
		}
		catch (GLib.Error e)
		{
			runner_app.show_error("Integration script error", "The web app integration script has not provided a valid response and caused an error: %s".printf(e.message));
			return true;
		}
		VariantIter iter = args.iterator();
		assert(iter.next("s", null));
		assert(iter.next("a{smv}", &iter));
		string key = null;
		Variant value = null;
		bool approved = false;
		while (iter.next("{smv}", &key, &value))
		{
			if (key == "approved")
				approved = value != null ? value.get_boolean() : false;
			else if (key == "newWindow" && value != null)
				new_window = value.get_boolean();
		}
		return approved;
	}
	
	private void ask_page_settings(string url, bool new_window, ref bool javascript_enabled, ref string? user_agent)
	{
		var builder = new VariantBuilder(new VariantType("a{smv}"));
		builder.add("{smv}", "url", new Variant.string(url));
		builder.add("{smv}", "newWindow", new Variant.boolean(new_window));
		builder.add("{smv}", "javascript", new Variant.boolean(javascript_enabled));
		builder.add("{smv}", "userAgent", user_agent != null ? new Variant.string(user_agent) : new Variant("mv", null));
		var args = new Variant("(s@a{smv})", "PageSettings", builder.end());
		try
		{
			env.call_function_sync("Nuvola.core.emit", ref args);
		}
		catch (GLib.Error e)
		{
			runner_app.show_error("Integration script error", "The web app integration script has not provided a valid response and caused an error: %s".printf(e.message));
			return;
		}
		VariantIter iter = args.iterator();
		assert(iter.next("s", null));
		assert(iter.next("a{smv}", &iter));
		string key = null;
		Variant value = null;
		while (iter.next("{smv}", &key, &value))
		{
			switch (key)
			{
			case "javascript":
				javascript_enabled = value != null ? value.get_boolean() : false;
				break;
			case "userAgent":
				user_agent = Drt.variant_to_string(value);
				break;
			}
		}
	}
	
	private void on_uri_changed(GLib.Object o, ParamSpec p)
	{
		var args = new Variant("(sms)", "UriChanged", web_view.uri);
		try
		{
			env.call_function_sync("Nuvola.core.emit", ref args);
		}
		catch (GLib.Error e)
		{
			runner_app.show_error("Integration script error", "The web app integration caused an error: %s".printf(e.message));
		}
	}
	
	private void on_is_loading_changed(GLib.Object o, ParamSpec p) {
		this.is_loading = web_view.is_loading;
	}
	
	private void on_back_forward_list_changed(WebKit.BackForwardListItem? item_added, void* items_removed)
	{
		can_go_back = web_view.can_go_back();
		can_go_forward = web_view.can_go_forward();
	}
	
	private void on_zoom_level_changed(GLib.Object o, ParamSpec p)
	{
		config.set_double(ZOOM_LEVEL_CONF, web_view.zoom_level);
	}
	
	private bool on_script_dialog(WebKit.ScriptDialog dialog)
	{
		bool handled = false;
		if (dialog.get_dialog_type() == WebKit.ScriptDialogType.ALERT)
			show_alert_dialog(ref handled, dialog.get_message());
		return handled;
	}
	
	private bool on_context_menu(WebKit.ContextMenu menu, Gdk.Event event, WebKit.HitTestResult hit_test_result)
	{
		webkit_context_menu(menu, event, hit_test_result);
		return false;
	}
}

public enum NetworkProxyType
{
	SYSTEM,
	DIRECT,
	HTTP,
	SOCKS;
	
	public static NetworkProxyType from_string(string type)
	{
		switch (type.down())
		{
		case "none":
		case "direct":
			return DIRECT;
		case "http":
			return HTTP;
		case "socks":
			return SOCKS;
		default:
			return SYSTEM;
		}
	}
	
	public string to_string()
	{
		switch (this)
		{
		case DIRECT:
			return "direct";
		case HTTP:
			return "http";
		case SOCKS:
			return "socks";
		default:
			return "system";
		}
	}
}

} // namespace Nuvola
