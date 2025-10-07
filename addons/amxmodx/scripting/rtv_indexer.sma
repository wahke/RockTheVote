/* 
 * RTV Map Indexer (optional helper)
 * Author: wahke.lu
 * Purpose: scan 'maps/' for .bsp files and write 'data/rockthevote_maps_index.txt'
 * Note: This is optional. Only needed if you want an automatic folder scan.
 */

#include <amxmodx>

public plugin_init()
{
    register_plugin("RTV Map Indexer", "1.0.0", "wahke.lu");
    set_task(2.0, "build_index", 12345);
}

public build_index()
{
    new path[128];
    new name[128];

    // open_dir/next_file are available in AMXX. If your AMXX lacks these,
    // you may need to use an alternative method or an extension.
    new DirHandle:dir = open_dir("maps");
    if (!dir)
    {
        server_print("[RTV] Could not open 'maps' directory.");
        return;
    }

    new File:f = fopen("data/rockthevote_maps_index.txt", "wt");
    if (!f)
    {
        server_print("[RTV] Could not open index file for writing.");
        close_dir(dir);
        return;
    }

    while (next_file(dir, name, charsmax(name)))
    {
        // Check extension
        if (containi(name, ".bsp") != -1)
        {
            // strip extension
            replace(name, charsmax(name), ".bsp", "");
            fprintf(f, "%s^n", name);
        }
    }

    close_dir(dir);
    fclose(f);
    server_print("[RTV] Wrote data/rockthevote_maps_index.txt");
}
