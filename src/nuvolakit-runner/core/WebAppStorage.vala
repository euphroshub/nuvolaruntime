/*
 * Copyright 2014-2018 Jiří Janoušek <janousek.jiri@gmail.com>
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

namespace Nuvola {

public class WebAppStorage : GLib.Object {
    public File config_dir {get; construct;}
    public File data_dir {get; construct;}
    public File cache_dir {get; construct;}

    public WebAppStorage(File config_dir, File data_dir, File cache_dir) {
        Object(config_dir: config_dir, data_dir: data_dir, cache_dir: cache_dir);
        try {
            Drt.System.make_dirs(config_dir);
            Drt.System.make_dirs(data_dir);
            Drt.System.make_dirs(cache_dir);
        }
        catch (GLib.Error e) {
            error("Failed to create directory. %s", e.message);
        }
    }

    /**
     * Returns the default path of cache subdir with given name, create it if it doesn't exist.
     *
     * @param path    Subdirectory path.
     * @return cache subdirectory
     */
    public File create_cache_subdir(string path) {
        File dir = cache_dir.get_child(path);
        try {
            Drt.System.make_dirs(dir);
        }
        catch (GLib.Error e) {
            warning("Failed to create directory '%s'. %s", dir.get_path(), e.message);
        }
        return dir;
    }

    /**
     * Returns the default path of data subdir with given name, create it if it doesn't exist.
     *
     * @param path    Subdirectory path.
     * @return data subdirectory
     */
    public File create_data_subdir(string path) {
        File dir = data_dir.get_child(path);
        try {
            Drt.System.make_dirs(dir);
        }
        catch (GLib.Error e) {
            warning("Failed to create directory '%s'. %s", dir.get_path(), e.message);
        }
        return dir;
    }
}

}
