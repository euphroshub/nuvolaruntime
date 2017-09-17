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

public class Nuvola.MediaPlayerBinding: ModelBinding<MediaPlayerModel>
{
	private const string TRACK_INFO_CHANGED = "track-info-changed";
	private const string TRACK_POSITION_CHANGED = "track-position-changed";
	private const string VOLUME_CHANGED = "volume-changed";
	
	public MediaPlayerBinding(Drt.RpcRouter router, WebWorker web_worker, MediaPlayerModel model)
	{
		base(router, web_worker, "Nuvola.MediaPlayer", model);
	}
	
	protected override void bind_methods()
	{
		bind("get-flag", Drt.RpcFlags.READABLE,
			"Returns boolean state of a particular flag or null if no such flag has been found.",
			handle_get_flag, {
			new Drt.StringParam("name", true, false, null, "Flag name, e.g. can-go-next, can-go-previous, can-play, can-pause, can-stop, can-rate"),
		});
		bind("set-flag", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE, null, handle_set_flag, {
			new Drt.StringParam("name", true, false),
			new Drt.BoolParam("state", true),

		});
		bind("set-track-info", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE, null, handle_set_track_info, {
			new Drt.StringParam("title", false, true),
			new Drt.StringParam("artist", false, true),
			new Drt.StringParam("album", false, true),
			new Drt.StringParam("state", false, true),
			new Drt.StringParam("artworkLocation", false, true),
			new Drt.StringParam("artworkFile", false, true),
			new Drt.DoubleParam("rating", false, 0.0),
			new Drt.DoubleParam("length", false, 0.0),
			new Drt.StringArrayParam("playbackActions", false),
		});
		bind("set-track-position", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE, null, handle_set_track_position, {
			new Drt.DoubleParam("position", false, 0.0)

		});
		bind("update-volume", Drt.RpcFlags.PRIVATE|Drt.RpcFlags.WRITABLE, null, handle_update_volume, {
			new Drt.DoubleParam("volume", false, 1.0)

		});
		bind("track-info", Drt.RpcFlags.READABLE, "Returns information about currently playing track.",
			handle_get_track_info, null);
		bind("volume", Drt.RpcFlags.READABLE, "Returns information about current volume.",
			handle_get_volume, null);
		bind("track-position", Drt.RpcFlags.READABLE, "Returns information about current track position.",
			handle_get_track_position, null);
		add_notification(TRACK_INFO_CHANGED, Drt.RpcFlags.WRITABLE|Drt.RpcFlags.SUBSCRIBE,
			"Sends a notification when track info is changed.");
		add_notification(TRACK_POSITION_CHANGED, Drt.RpcFlags.WRITABLE|Drt.RpcFlags.SUBSCRIBE,
			"Sends a notification when track position is changed.");
		add_notification(VOLUME_CHANGED, Drt.RpcFlags.WRITABLE|Drt.RpcFlags.SUBSCRIBE,
			"Sends a notification when volume is changed.");
		model.set_rating.connect(on_set_rating);
	}
	
	private void handle_set_track_info(Drt.RpcRequest request) throws Drt.RpcError
	{
		check_not_empty();
		var title = request.pop_string();
		var artist = request.pop_string();
		var album = request.pop_string();
		var state = request.pop_string();
		var artwork_location = request.pop_string();
		var artwork_file = request.pop_string();
		var rating = request.pop_double();
		var length = request.pop_double();
		model.set_track_info(title, artist, album, state, artwork_location, artwork_file, rating, (int64) length);
		
		SList<string> playback_actions = null;
		var actions = request.pop_strv();
		foreach (var action in actions)
			playback_actions.prepend(action);
		playback_actions.reverse();
		model.playback_actions = (owned) playback_actions;
		
		emit(TRACK_INFO_CHANGED);		
		request.respond(new Variant.boolean(true));
	}
	
	private void handle_get_track_info(Drt.RpcRequest request) throws Drt.RpcError
	{
		check_not_empty();
		var builder = new VariantBuilder(new VariantType("a{smv}"));
		builder.add("{smv}", "title", Drt.new_variant_string_or_null(model.title));
		builder.add("{smv}", "artist", Drt.new_variant_string_or_null(model.artist));
		builder.add("{smv}", "album", Drt.new_variant_string_or_null(model.album));
		builder.add("{smv}", "state", Drt.new_variant_string_or_null(model.state));
		builder.add("{smv}", "artworkLocation", Drt.new_variant_string_or_null(model.artwork_location));
		builder.add("{smv}", "artworkFile", Drt.new_variant_string_or_null(model.artwork_file));
		builder.add("{smv}", "rating", new Variant.double(model.rating));
		request.respond(builder.end());
	}
	
	private void handle_set_track_position(Drt.RpcRequest request) throws Drt.RpcError
	{
		check_not_empty();
		var position = request.pop_double();
		model.track_position = (int64) position;
		emit(TRACK_POSITION_CHANGED);
		request.respond(new Variant.boolean(true));
	}
	
	private void handle_get_track_position(Drt.RpcRequest request) throws Drt.RpcError
	{
		check_not_empty();
		request.respond(new Variant.double((double) model.track_position));
	}
	
	private void handle_update_volume(Drt.RpcRequest request) throws Drt.RpcError
	{
		check_not_empty();
		var volume = request.pop_double();
		model.volume = volume;
		emit(VOLUME_CHANGED);
		request.respond(new Variant.boolean(true));
	}
	
	private void handle_get_volume(Drt.RpcRequest request) throws Drt.RpcError
	{
		check_not_empty();
		request.respond(new Variant.double(model.volume));
	}
	
	private void handle_set_flag(Drt.RpcRequest request) throws Drt.RpcError
	{
		check_not_empty();
		var name = request.pop_string();
		var state = request.pop_bool();
		bool handled = false;
		switch (name)
		{
		case "can-go-next":
		case "can-go-previous":
		case "can-play":
		case "can-pause":
		case "can-stop":
		case "can-rate":
		case "can-seek":
		case "can-change-volume":
			handled = true;
			GLib.Value value = GLib.Value(typeof(bool));
			value.set_boolean(state);
			model.@set_property(name, value);
			break;
		default:
			warning("Unknown flag '%s'", name);
			break;
		}
		request.respond(new Variant.boolean(handled));
	}
	
	private void handle_get_flag(Drt.RpcRequest request) throws Drt.RpcError
	{
		check_not_empty();
		var name = request.pop_string();
		switch (name)
		{
		case "can-go-next":
		case "can-go-previous":
		case "can-play":
		case "can-pause":
		case "can-stop":
		case "can-rate":
		case "can-seek":
		case "can-change-volume":
			GLib.Value value = GLib.Value(typeof(bool));
			model.@get_property(name, ref value);
			request.respond(new Variant.boolean(value.get_boolean()));
			break;
		default:
			warning("Unknown flag '%s'", name);
			request.respond(null);
			break;
		}
	}
	
	private void on_set_rating(double rating)
	{
		if (!model.can_rate)
		{
			warning("Rating is not enabled");
			return;
		}
		
		try
		{
			var payload = new Variant("(sd)", "RatingSet", rating);
			call_web_worker("Nuvola.mediaPlayer.emit", ref payload);
		}
		catch (GLib.Error e)
		{
			warning("Communication failed: %s", e.message);
		}
	}
}
