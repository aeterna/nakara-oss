aeterna_camera saves photos in this folder as <id>.jpg.

Keep this folder when you upgrade the resource: replacing the resource folder deletes every photo.
Keep the server KVP database too (FXServer stores it outside resource folders); it holds the photo index.
A deleted photo leaves an empty (zero-byte) file here; the next photo reuses it. You may delete zero-byte files while
the server is stopped.
