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

#if HAVE_CEF
namespace Nuvola {

public class CefOptions : WebOptions {
	public override VersionTuple engine_version {get; protected set;}
	public CefGtk.WebContext default_context {get; private set; default = null;}
	public bool widevine_required {get; set; default = false;}
	public bool flash_required {get; private set; default = false;}
	
	public CefOptions(WebAppStorage storage) {
		base(storage);
	}
	
	construct {
		engine_version = VersionTuple.parse(Cef.get_chromium_version());
	}
	
	public override string get_display_name() {
		return "Chromium " + Cef.get_chromium_version();
	}
	
	public override async void gather_format_support_info(WebApp web_app) {
		init(web_app);
		var result = CefGtk.get_init_result();
		var widevine = result.widevine_plugin;
		if (widevine != null && !widevine.registration_complete) {
			SourceFunc cb = gather_format_support_info.callback;
			var handler_id = widevine.notify["registration-complete"].connect_after(() => Idle.add((owned) cb));
			yield;
			widevine.disconnect(handler_id);
		}
	}
	
	public void init(WebApp web_app) {
		if (default_context == null) {
			var user_agent = WebOptions.make_user_agent(web_app.user_agent);
			if (user_agent != null) {
				user_agent += " Nuvola/" + Nuvola.get_short_version();
			}
			var product = "Chrome/%s Nuvola/%s".printf(Cef.get_chromium_version(), Nuvola.get_short_version());
			CefGtk.init(widevine_required, flash_required, user_agent, product);
			default_context = new CefGtk.WebContext(GLib.Environment.get_user_config_dir() + "/cefium");
		}
	}
	
	public override WebEngine create_web_engine(WebApp web_app) {
		init(web_app);
		return new CefEngine(this, web_app);
	}
	
	public override Drt.RequirementState supports_requirement(string type, string? parameter, out string? error) {
		error = null;
		switch (type) {
		case "chromium":
		case "chrome":
			if (parameter == null) {
				return Drt.RequirementState.SUPPORTED;
			}
			var param = parameter.strip().down();
			if (param[0] == 0) {
				return Drt.RequirementState.SUPPORTED;
			}
			var versions = param.split(".");
			if (versions.length > 4) {
				error = "%s[] received invalid version parameter '%s'.".printf(type, param);
				return Drt.RequirementState.ERROR;
			}
			uint[] uint_versions = {0, 0, 0, 0};
			for (var i = 0; i < versions.length; i++) {
				var version = int.parse(versions[i]);
				if (i < 0) {
					error = "%s[] received invalid version parameter '%s'.".printf(type, param);
					return Drt.RequirementState.ERROR;
				}
				uint_versions[i] = (uint) version;
			}
			return (engine_version.gte(VersionTuple.uintv(uint_versions))
				? Drt.RequirementState.SUPPORTED : Drt.RequirementState.UNSUPPORTED);
		default:
			return Drt.RequirementState.UNSUPPORTED;
		}
	}
	
	public override Drt.RequirementState supports_feature(string name, out string? error) {
		error = null;
		switch (name) {
		case "mse":
			return Drt.RequirementState.SUPPORTED;
		case "widevine":
			widevine_required = true;
			var result = CefGtk.get_init_result();
			if (result == null) {
				return Drt.RequirementState.UNKNOWN;
			}
			var widevine = result.widevine_plugin;
			return (widevine != null && widevine.available ?
				Drt.RequirementState.SUPPORTED : Drt.RequirementState.UNSUPPORTED);
		case "flash":
			flash_required = true;
			var result = CefGtk.get_init_result();
			if (result == null) {
				return Drt.RequirementState.UNKNOWN;
			}
			var flash = result.flash_plugin;
			return (flash != null && flash.available
				? Drt.RequirementState.SUPPORTED : Drt.RequirementState.UNSUPPORTED);
		default:
			return Drt.RequirementState.UNSUPPORTED;
		}
	}
	
	public override Drt.RequirementState supports_codec(string name, out string? error) {
		error = null;
		switch (name) {
		case "mp3":
		case "h264":
			return Drt.RequirementState.SUPPORTED;
		default:
			return Drt.RequirementState.UNSUPPORTED;
		}
	}
	
	public override string[] get_format_support_warnings() {
		string[] warnings = {};
		var result = CefGtk.get_init_result();
		if (result != null) {
			if (result.flash_plugin != null && result.flash_plugin.registration_error != null) {
				warnings += Markup.printf_escaped("Failed to load Flash plugin: %s",
					result.flash_plugin.registration_error);
			}
			if (result.widevine_plugin != null && result.widevine_plugin.registration_error != null) {
				warnings += Markup.printf_escaped("Failed to load Widevine plugin: %s",
					result.widevine_plugin.registration_error);
			}
		}
		return warnings;
	}
}

} // namespace Nuvola
#endif