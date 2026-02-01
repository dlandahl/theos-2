
#import "Basic";
#import "File";

#import "FAT16";

#run {
    {
        image_file := read_entire_file("disk_image.img");

        disk_image := fat16_parse_disk_image(image_file);
        root       := fat16_get_root_directory(*disk_image);

        fat16_create_directory(root, "THEOS");
        fat16_write_file(root, "THEOS/TEST", "The old gentleman's undoubting, unquestioning simplicity has a rare freshness about it in these matter-of-fact railroading and telegraphing days.");
        fat16_copy_fat_table(*disk_image);

        write_entire_file("disk_image.img", disk_image.all_file_data);
    }
}
