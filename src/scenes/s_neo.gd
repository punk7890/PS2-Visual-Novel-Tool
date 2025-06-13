extends Control

@onready var file_load_iso: FileDialog = $FILELoadISO
@onready var file_load_folder: FileDialog = $FILELoadFOLDER

enum enc_type {
	NONE,
	KEYORINA,
	KONNYAKU,
	PURECURE,
	PIAGO,
	PARFAIT
}

var encryption_selected: int = enc_type.KONNYAKU

# Used in PIAGO encryption. Based on encrypted u32 int at 0xC in ROM.BIN
var global_key: int = 0
# Used by PURECURE encryption.
var lookup_tbl: PackedByteArray

var folder_path: String
var selected_file: String = ""
var chose_file: bool = false
var chose_folder: bool = false
var debug_out: bool = false
var debug_raw_out: bool = false
var remove_alpha: bool = true
var remove_alpha_bup: bool = false

# Table used for CRC - not needed
#var xor_table: PackedByteArray


#func _ready() -> void:
	#make_xor_table()


func _process(_delta: float) -> void:
	if chose_file and chose_folder:
		extractIso()
		selected_file = ""
		chose_file = false
		chose_folder = false


func extractIso() -> void:
	var in_file: FileAccess
	var out_file: FileAccess
	var rom_file: FileAccess
	var fail: bool = false
	var dvd_str: String
	var rom_off: int
	var rom_size: int
	var buff: PackedByteArray
	var xor_tbl: PackedByteArray
	var hdr_bytes: PackedByteArray
	var num_files: int
	var f_name: String
	var f_name_off: int
	var last_name_pos: int
	var last_tbl_pos: int
	var f_offset: int
	var f_key: int
	var f_size: int
	var file_tbl: int
	var pos: int
	var made_folders: bool = false
	var checked_2nd_folder: bool = false
	var folders: Dictionary = {}
	var current_folder: String
	var last_folder: String
	var rom_offsets: Dictionary = {
	"KONNYAKU": 0x445C0, # Kono Aozora Ni
	"HIGURASI": 0x445C0, # Higurashi no Naku Koro ni Matsuri
	"HGRSMTRR": 0x445C0, # Higurashi no Naku Koro ni - Matsuri - Kakera Asobi 
	"PURECURE": 0x445C0, # Pure x Cure Recovery  (Angle Maneuver engine)
	"KEYORINA": 0x445C0, # Yoake Mae Yori Ruriiro na: Brighter than Dawning Blue
	"PIAGO": 0x445C0, # Pia Carrot he Youkoso!! G.O. Summer Fair (Angel Maneuver engine)
	"UTMC": 0x445C0, # Under the Moon: Crescent
	"PARFAIT": 0x124F80, # Parfait - Chocolat Second Style
	"LDROPS": 0x445C0, # Love Drops
	"CHANTER": 0x445C0, # Chanter
	"TOGADOG": 0x445C0 # Togainu no Chi
	}
	
	# TODO: There's a lot of encrypted data before ROM start, but it seems not needed? What is it all?
	# Check BUPs for any weird missing / distorted image parts, as the method for PIC2s may need to be applied here.
	# Check whatever is in .lzs files as I haven't fully verified if the data is correct.
	# Katakamuna uses a different compression. Only extraction supported for now.
	# Handle .txa images
	# Handle .wip decompression
	
	in_file = FileAccess.open(selected_file, FileAccess.READ)
	
	# All other games besides Katakamuna and Sugar + Spice have a dvd name.
	if Main.game_type == Main.KATAKAMUNA:
		in_file.seek(0xC3500000)
		hdr_bytes = in_file.get_buffer(3)
		dvd_str = hdr_bytes.get_string_from_ascii()
		if dvd_str == "ROM":
			rom_off = 0x186A00
			encryption_selected = enc_type.NONE
		else:
			OS.alert("ISO doesn't appear to be Katakamuna.")
			return
	elif Main.game_type == Main.SUGARSPICE:
		in_file.seek(0x1F4000)
		hdr_bytes = in_file.get_buffer(3)
		dvd_str = hdr_bytes.get_string_from_ascii()
		if dvd_str == "ROM":
			rom_off = 0x3E8
			encryption_selected = enc_type.PIAGO
		else:
			OS.alert("ISO doesn't appear to be Sugar + Spice.")
			return
	elif Main.game_type == Main.CHOCOLAT:
		in_file.seek(0x73F78000)
		hdr_bytes = in_file.get_buffer(3)
		dvd_str = hdr_bytes.get_string_from_ascii()
		if dvd_str == "ROM":
			rom_off = 0xE7EF0
			encryption_selected = enc_type.PARFAIT
		else:
			OS.alert("ISO doesn't appear to be Sugar + Spice.")
			return
	else:
		# Check if DVD name matches
		in_file.seek(0x83071)
		hdr_bytes = in_file.get_buffer(8)
		dvd_str = hdr_bytes.get_string_from_ascii()
		if dvd_str in rom_offsets:
			rom_off = rom_offsets[dvd_str]
		else:
			var expected_str: String = ", ".join(rom_offsets.keys())
			OS.alert("%s doesn't match known offset! Expected one of: %s, but got: %s." % [selected_file, expected_str, dvd_str])
			return
			
	var shift_jis_dic: Dictionary = ComFuncs.make_shift_jis_dic()
	# Set decryption type
	if dvd_str == "KEYORINA":
		encryption_selected = enc_type.KEYORINA
	elif dvd_str == "HIGURASI":
		encryption_selected = enc_type.KONNYAKU
	elif dvd_str == "HGRSMTRR":
		encryption_selected = enc_type.PIAGO
	elif dvd_str == "KONNYAKU":
		encryption_selected = enc_type.KONNYAKU
	elif dvd_str == "LDROPS":
		encryption_selected = enc_type.KONNYAKU
	elif dvd_str == "PIAGO":
		encryption_selected = enc_type.PIAGO
	elif dvd_str == "PARFAIT":
		encryption_selected = enc_type.PARFAIT
	elif dvd_str == "PURECURE":
		encryption_selected = enc_type.PURECURE
	elif dvd_str == "CHANTER":
		encryption_selected = enc_type.PURECURE
	elif dvd_str == "TOGADOG":
		encryption_selected = enc_type.PIAGO
	elif dvd_str == "UTMC":
		encryption_selected = enc_type.PIAGO
		
	rom_off *= 0x800
	
	in_file.seek(rom_off + 8)
	rom_size = in_file.get_32()
	rom_size *= 0x800
	
	in_file.seek(rom_off)
	buff = in_file.get_buffer(rom_size)
	
	if encryption_selected == enc_type.KONNYAKU or encryption_selected == enc_type.KEYORINA:
		# Xor table is after ROM offset with the same size
		xor_tbl = in_file.get_buffer(rom_size)
		buff = decrypt_rom_header(buff, xor_tbl)
	elif encryption_selected == enc_type.PIAGO:
		global_key = buff.decode_u32(0xC) # Retrieve global key from header of ROM.BIN
		buff = decrypt_rom_header_PIAGO(buff)
	elif encryption_selected == enc_type.PARFAIT:
		buff = decrypt_rom_header_PARFAIT(buff)
	elif encryption_selected == enc_type.PURECURE:
		var key: int
		if dvd_str == "PURECURE":
			key = 0x151F2326 # Key is derived from a CRC lookup table to verify files, but we only need the last key from the table.
		elif dvd_str == "CHANTER":
			key = 0x3D378B65
		# Make lookup table for file decryption
		var keys: PackedInt64Array = decrypt_int_PURECURE(key) # Actually loads 2 u32s but Godot wraps around if loaded as a 32 array (treats as signed).
		var off: int = 0
		while off < 0x100F:
			lookup_tbl.append(keys[1] & 0xFF)
			keys = decrypt_int_PURECURE(keys[0])
			off += 1
			
		lookup_tbl.append(0) # Last byte is zero in game's memory.
		
		out_file = FileAccess.open(folder_path + "/!LOOKUP.TBL", FileAccess.WRITE)
		out_file.store_buffer(lookup_tbl)
		out_file.close()
		
		key = buff.decode_u32(0xC) # Initial key is at 0xC in ROM.BIN
		keys = decrypt_int_PURECURE(key)
		off = 0x10
		while off < rom_size:
			var byte: int = buff.decode_u8(off) ^ keys[1]
			buff.encode_s8(off, byte)
			keys = decrypt_int_PURECURE(keys[0])
			off += 1
			
	
	out_file = FileAccess.open(folder_path + "/!ROM.BIN", FileAccess.WRITE)
	out_file.store_buffer(buff)
	out_file.close()
	buff.clear()
	
	rom_file = FileAccess.open(folder_path + "/!ROM.BIN", FileAccess.READ)
	
	pos = 0x10
	if encryption_selected == enc_type.NONE or encryption_selected == enc_type.PARFAIT: # Katakamuna/PARFAIT aligns to 0x80 for tables
		pos = (pos + 0x7F) & ~0x7F
	while pos < rom_size:
		rom_file.seek(pos)
		if rom_file.eof_reached():
			break
			
		file_tbl = pos
		num_files = rom_file.get_32()
		if num_files == 0:
			break
		last_tbl_pos = rom_file.get_position()
		for file in num_files:
			rom_file.seek(last_tbl_pos)
			f_name_off = rom_file.get_32() # if highest 32 bit is 0x80 is a folder.
			f_offset = rom_file.get_32()
			f_key = f_offset # Used as a key in PUREPURE/PIAGO encryption
			f_size = rom_file.get_32()
			last_tbl_pos = rom_file.get_position()
			if f_name_off > 0x7FFFFFFF:
				rom_file.seek(file_tbl + f_name_off & 0x7FFFFFFF)
				var result: Array = ComFuncs.find_end_bytes_file(rom_file, 0)
				last_name_pos = result[0]
				var temp_folder: String = ComFuncs.convert_jis_packed_byte_array(result[1], shift_jis_dic).get_string_from_utf8().lstrip(".")
				if !last_name_pos % 16 == 0:
					last_name_pos = (last_name_pos + 15) & ~15
					
				if !temp_folder == "":
					if temp_folder not in folders:
						folders[temp_folder] = {}
					folders[temp_folder]["ids"] = [[f_offset, f_size]]
				if made_folders:
					rom_file.seek(last_tbl_pos + 4)
					var next_f_id: int = rom_file.get_32()
					var next_f_id2: int = rom_file.get_32()
					if temp_folder == "" and f_offset > 1:
						for key in folders.keys():
							if [f_offset, f_size] in folders[key].get("ids", []):
								if !checked_2nd_folder:
									var parts: PackedStringArray = current_folder.split("/")
									if parts.size() > 1:
										current_folder = "/".join(parts.slice(0, 1))
									last_folder = current_folder
									current_folder = key
									temp_folder = key
									break
								temp_folder = key
								break
					if temp_folder == current_folder and !checked_2nd_folder:
						for key in folders.keys():
							if [next_f_id, next_f_id2] in folders[key].get("ids", []):
								current_folder = last_folder + "/" + current_folder
								checked_2nd_folder = true
								break
				continue
			
			rom_file.seek(file_tbl + f_name_off)
			# Because Godot hates Shift-JIS, we must get each byte manually and detect where it ends.
			var result: Array = ComFuncs.find_end_bytes_file(rom_file, 0)
			last_name_pos = result[0]
			f_name = ComFuncs.convert_jis_packed_byte_array(result[1], shift_jis_dic).get_string_from_utf8()
			
			# Use for debugging certain file(s)
			#if f_name.get_extension() != "pic":
				#if !last_name_pos % 16 == 0:
					#last_name_pos = (last_name_pos + 15) & ~15
				#continue
			
			f_offset = (f_offset * 0x800) + rom_off
			in_file.seek(f_offset)
			buff = in_file.get_buffer(f_size)
			
			# Decrypt bytes in sectors
			if encryption_selected == enc_type.KONNYAKU:
				var dec_pos: int = 0
				while dec_pos < f_size:
					for i in range(0, 0x10):
						if dec_pos + i >= f_size:
							break
						var bytes: int = buff.decode_u8(dec_pos + i)
						buff.encode_u8(dec_pos + i, bytes ^ 0xFF)
					dec_pos += 0x800
			elif encryption_selected == enc_type.PIAGO:
				buff = decrypt_mem_file_PIAGO(buff, global_key, f_key)
			elif encryption_selected == enc_type.PURECURE:
				buff = decrypt_mem_file_PURECURE(buff, f_key)
				
			if !last_name_pos % 16 == 0: # Align to 0x10 boundary for next table start when i reaches num_files
				last_name_pos = (last_name_pos + 15) & ~15
				
			if debug_out:
				if made_folders and current_folder:
					f_name = current_folder + "/" + f_name
					var dir: DirAccess = DirAccess.open(folder_path)
					dir.make_dir_recursive(folder_path + "/" + current_folder)
				out_file = FileAccess.open(folder_path + "/%s" % f_name + ".ORG", FileAccess.WRITE)
				out_file.store_buffer(buff)
				out_file.close()
				
				f_name = f_name.get_file()
			
			# Decompression ONLY for these files (other file types need checking)
			if f_name.get_extension() == "pic" or f_name.get_extension() == "lzs" or f_name.get_extension() == "bup" or f_name.get_extension() == "bup_":
				# *** Remove this section later
				if Main.game_type == Main.KATAKAMUNA:
					if made_folders and current_folder:
						f_name = current_folder + "/" + f_name
						var dir: DirAccess = DirAccess.open(folder_path)
						dir.make_dir_recursive(folder_path + "/" + current_folder)
					out_file = FileAccess.open(folder_path + "/%s" % f_name, FileAccess.WRITE)
					out_file.store_buffer(buff)
					out_file.close()
					
					f_name = f_name.get_file()
					
					print("%08X " % f_offset, "%08X " % f_size, "%s" % folder_path + "/%s " % f_name)
					continue
				# ***
				buff = decompress_sneo(buff)
			if f_name.get_extension() == "img" and current_folder != "bustup":
				# For Parfait. No BUP support yet.
				# arr_dat[0] is the full decompressed buffer, [1] is the png image.
				var arr_dat: Array = process_img(buff)
				buff = arr_dat[0]
				if made_folders and current_folder:
					f_name = current_folder + "/" + f_name
					var dir: DirAccess = DirAccess.open(folder_path)
					dir.make_dir_recursive(folder_path + "/" + current_folder)
					
				if debug_raw_out:
					out_file = FileAccess.open(folder_path + "/%s" % f_name + ".DEC", FileAccess.WRITE)
					out_file.store_buffer(buff)
					out_file.close()
					
				var png: Image = arr_dat[1]
				png.save_png(folder_path + "/%s" % f_name + ".PNG")
				
				print("%08X " % f_offset, "%08X " % f_size, "%s" % folder_path + "/%s " % f_name)
				continue
				
			hdr_bytes = buff.slice(0, 4)
			var hdr_str: String = hdr_bytes.get_string_from_ascii()
			if hdr_str == "PIC2":
				if made_folders and current_folder:
					f_name = current_folder + "/" + f_name
					var dir: DirAccess = DirAccess.open(folder_path)
					dir.make_dir_recursive(folder_path + "/" + current_folder)
					
				if debug_raw_out:
					out_file = FileAccess.open(folder_path + "/%s" % f_name + ".DEC", FileAccess.WRITE)
					out_file.store_buffer(buff)
					out_file.close()
				
				# For dummy images in Yoake Mae Yori Ruriiro na: Brighter than Dawning Blue
				if buff.size() == 0:
					print_rich("[color=yellow]Skipping %s as num images is 0[/color]" % f_name)
					print("%08X " % f_offset, "%08X " % f_size, "%s" % folder_path + "/%s " % f_name)
					continue
					
				var png: Image = process_pic2ps2_image(buff)
				png.save_png(folder_path + "/%s" % f_name + ".PNG")
				
				print("%08X " % f_offset, "%08X " % f_size, "%s" % folder_path + "/%s " % f_name)
				continue
			if hdr_str == "PIC ":
				# TODO: At 0x001522C8.
				# Comp size is after palette
				# Reads byte + 4 after comp size for decompression routine
				pass
			elif hdr_str == "BUP2":
				if made_folders and current_folder:
					f_name = current_folder + "/" + f_name
					var dir: DirAccess = DirAccess.open(folder_path)
					dir.make_dir_recursive(folder_path + "/" + current_folder)
						
				if debug_raw_out:
					out_file = FileAccess.open(folder_path + "/%s" % f_name + ".DEC", FileAccess.WRITE)
					out_file.store_buffer(buff)
					out_file.close()
				
				var png: Image = process_bup2ps2_image(buff)
				png.save_png(folder_path + "/%s" % f_name + ".PNG")
				
				print("%08X " % f_offset, "%08X " % f_size, "%s" % folder_path + "/%s " % f_name)
				continue
			elif hdr_str == "OLZP" or f_name.get_extension() == "vpp": # Sugar + Spice headers
				# Some vpps are compressed? c00.vpp?
				if made_folders and current_folder:
					f_name = current_folder + "/" + f_name
					var dir: DirAccess = DirAccess.open(folder_path)
					dir.make_dir_recursive(folder_path + "/" + current_folder)
						
				if debug_raw_out:
					out_file = FileAccess.open(folder_path + "/%s" % f_name + ".DEC", FileAccess.WRITE)
					out_file.store_buffer(buff)
					out_file.close()
					
				if hdr_str == "OLZP" and f_name.get_extension() != "vpp": # vpps aren't compressed.
					buff = decompress_lzss_sneo(buff)
				
				hdr_bytes = buff.slice(0, 4)
				hdr_str = hdr_bytes.get_string_from_ascii()
				if hdr_str != "VPF0": # Contains multiple image parts
					var imgs: Array[Image] = process_vpf_images(buff)
					for i in range(0, imgs.size()):
						var png: Image = imgs[i]
						png.save_png(folder_path + "/%s" % f_name + "_%03d" % i + ".PNG")
				elif hdr_str == "VPF0": # Only a single image
					var png: Image = process_vpf_single_image(buff)
					png.save_png(folder_path + "/%s" % f_name + ".PNG")
					
				print("%08X " % f_offset, "%08X " % f_size, "%s" % folder_path + "/%s " % f_name)
				continue
			elif hdr_str == "VPF0": # Sugar + Spice single image header
				if made_folders and current_folder:
					f_name = current_folder + "/" + f_name
					var dir: DirAccess = DirAccess.open(folder_path)
					dir.make_dir_recursive(folder_path + "/" + current_folder)
						
				if debug_raw_out:
					out_file = FileAccess.open(folder_path + "/%s" % f_name + ".DEC", FileAccess.WRITE)
					out_file.store_buffer(buff)
					out_file.close()
					
				var png: Image = process_vpf_single_image(buff)
				png.save_png(folder_path + "/%s" % f_name + ".PNG")
					
				print("%08X " % f_offset, "%08X " % f_size, "%s" % folder_path + "/%s " % f_name)
				continue
			if made_folders and current_folder:
				f_name = current_folder + "/" + f_name
				var dir: DirAccess = DirAccess.open(folder_path)
				dir.make_dir_recursive(folder_path + "/" + current_folder)
			out_file = FileAccess.open(folder_path + "/%s" % f_name, FileAccess.WRITE)
			out_file.store_buffer(buff)
			out_file.close()
			
			print("%08X " % f_offset, "%08X " % f_size, "%s" % folder_path + "/%s " % f_name)
		
		last_folder = ""
		made_folders = true
		checked_2nd_folder = false
		pos = last_name_pos
		if encryption_selected == enc_type.NONE or encryption_selected == enc_type.PARFAIT:
			pos = (pos + 0x7F) & ~0x7F
			
	print_rich("[color=green]Finished![/color]")
	lookup_tbl.clear()
	
	
func process_pic2ps2_image(data: PackedByteArray) -> Image:
	# Extract image dimensions
	var final_width: int = data.decode_u16(0x10)
	var final_height: int = data.decode_u16(0x12)

	# Extract palette data (1024 colors, 0x400 bytes)
	var palette_offset: int = data.decode_u32(0x18)
	var palette: PackedByteArray = PackedByteArray()
	for i in range(0, 0x400):
		palette.append(data.decode_u8(palette_offset + i))

	# Unswizzle the palette
	palette = ComFuncs.unswizzle_palette(palette, 32)
	#if remove_alpha:
		#for i in range(0, 0x400, 4):
			#palette.encode_u8(i + 3, 255)

	# Create the final image with a size large enough to fit all parts
	var final_image: Image = Image.create(final_width, final_height, false, Image.FORMAT_RGBA8)
	if remove_alpha:
		final_image = Image.create(final_width, final_height, false, Image.FORMAT_RGB8)

	# Read number of parts
	var num_parts: int = data.decode_u32(0x1C)

	# Start reading parts from offset 0x20
	var part_info_offset: int = 0x20
	var image_data_offset: int = palette_offset + 0x400

	for i in range(num_parts):
		# Read part information
		var part_x: int = data.decode_u16(part_info_offset + 0x0)
		var part_y: int = data.decode_u16(part_info_offset + 0x2)
		var part_width: int = data.decode_u16(part_info_offset + 0x4)
		var part_height: int = data.decode_u16(part_info_offset + 0x6)

		# Calculate part size and extract data
		var part_size: int = part_width * part_height
		var part_data: PackedByteArray = data.slice(image_data_offset, image_data_offset + part_size)
		image_data_offset += part_size

		# Break the part into tiles (128x128 or smaller)
		var tiles_across: int = ceil(part_width / 128.0)
		var tiles_down: int = ceil(part_height / 128.0)

		# Process each tile
		for ty in range(tiles_down):
			for tx in range(tiles_across):
				# Calculate the position and size of the tile
				var tile_offset_x: int = tx * 128
				var tile_offset_y: int = ty * 128
				var tile_width: int = min(128, part_width - tile_offset_x)
				var tile_height: int = min(128, part_height - tile_offset_y)

				# Create a new image for the tile
				var tile_image: Image = Image.create(tile_width, tile_height, false, Image.FORMAT_RGBA8)
				if remove_alpha:
					tile_image = Image.create(tile_width, tile_height, false, Image.FORMAT_RGB8)
				

				# Process the pixels for the tile
				for y in range(tile_height):
					for x in range(tile_width):
						# Correct index calculation relative to this part
						var local_x: int = tile_offset_x + x
						var local_y: int = tile_offset_y + y
						var index: int = local_x + local_y * part_width
						var palette_index: int = part_data[index]
						var r: int = palette[palette_index * 4 + 0]
						var g: int = palette[palette_index * 4 + 1]
						var b: int = palette[palette_index * 4 + 2]
						var a: int = palette[palette_index * 4 + 3]
						if remove_alpha:
							tile_image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0))
						else:
							tile_image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0))
				
				# Test tile
				#tile_image.save_png(folder_path + "/%02d" % i + ".PNG")
				#var tile: FileAccess = FileAccess.open(folder_path + "/%02d" % i + ".PART", FileAccess.WRITE)
				#tile.store_buffer(part_data)
				# Place the tile into the final image at the correct position
				for y in range(tile_height):
					for x in range(tile_width):
						var pixel: Color = tile_image.get_pixel(x, y)
						final_image.set_pixel(part_x + tile_offset_x + x, part_y + tile_offset_y + y, pixel)

		# Update part info offset for the next part
		part_info_offset += 0x10

	return final_image
	
	
func process_bup2ps2_image(data: PackedByteArray) -> Image:
	# May need to be updated in the future.
	
	# Extract image dimensions
	var image_width: int = data.decode_u16(0x14)
	var image_height: int = data.decode_u16(0x16)

	# Extract palette data (1024 colors, 0x400 bytes)
	var palette_offset: int = data.decode_u32(0x18)
	var palette: PackedByteArray = PackedByteArray()
	for i in range(0, 0x400):
		palette.append(data.decode_u8(palette_offset + i))

	# Unswizzle the palette
	palette = ComFuncs.unswizzle_palette(palette, 32)

	# If alpha needs to be removed, set it to 255
	#if remove_alpha_bup:
		#for i in range(0, 0x400, 4):
			#palette.encode_u8(i + 3, 255)

	# Extract raw pixel data
	var image_data_offset: int = palette_offset + 0x400
	var pixel_data: PackedByteArray = data.slice(image_data_offset, image_data_offset + image_width * image_height)

	# Create the image object
	var image: Image = Image.create(image_width, image_height, false, Image.FORMAT_RGBA8)
	if remove_alpha_bup:
		image = Image.create(image_width, image_height, false, Image.FORMAT_RGB8)

	# Process the pixel data and apply the palette
	for y in range(image_height):
		for x in range(image_width):
			var pixel_index: int = pixel_data[x + y * image_width]
			var r: int = palette[pixel_index * 4 + 0]
			var g: int = palette[pixel_index * 4 + 1]
			var b: int = palette[pixel_index * 4 + 2]
			var a: int = palette[pixel_index * 4 + 3]
			if remove_alpha_bup:
				image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0))
			else:
				image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0))

	return image
	

func process_img(data: PackedByteArray) -> Array:
	# Used by Parfait. Doesn't support BUPs yet, as there's multiple data in them.
	var hdr_bytes: PackedByteArray = data.slice(0, 4)
	var hdr_str = hdr_bytes.get_string_from_ascii()
	if hdr_str != "IMG ":
		push_error("Not a valid IMG header.")
		return Array()
	
	
	# Extract image dimensions
	var image_width: int = data.decode_u16(0x14)
	var image_height: int = data.decode_u16(0x16)

	# Extract palette data (1024 colors, 0x400 bytes)
	var palette_offset: int = 0x18
	var palette: PackedByteArray = PackedByteArray()
	for i in range(0, 0x400):
		palette.append(data.decode_u8(palette_offset + i))

	# Unswizzle the palette
	palette = ComFuncs.unswizzle_palette(palette, 32)

	# If alpha needs to be removed, set it to 255
	#if remove_alpha:
		#for i in range(0, 0x400, 4):
			#palette.encode_u8(i + 3, 255)

	# Extract raw pixel data
	var image_data_offset: int = palette_offset + 0x400
	var dec_size: int = data.decode_u32(image_data_offset + 4)
	var pixel_data: PackedByteArray = ComFuncs.decompLZSS(data.slice(image_data_offset + 8), data.size(), dec_size)

	# Create the image object
	var image: Image = Image.create(image_width, image_height, false, Image.FORMAT_RGBA8)
	if remove_alpha:
		image = Image.create(image_width, image_height, false, Image.FORMAT_RGB8)

	# Process the pixel data and apply the palette
	for y in range(image_height):
		for x in range(image_width):
			var pixel_index: int = pixel_data[x + y * image_width]
			var r: int = palette[pixel_index * 4 + 0]
			var g: int = palette[pixel_index * 4 + 1]
			var b: int = palette[pixel_index * 4 + 2]
			var a: int = palette[pixel_index * 4 + 3]
			if remove_alpha:
				image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0))
			else:
				image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0))
			
	var dat_arr: Array
	dat_arr.append(pixel_data)
	dat_arr.append(image)
	return dat_arr
	
	
func process_vpf_images(data: PackedByteArray) -> Array[Image]:
	# Since its not very clear what these header offsets do, we scan each offset and keep track of visited offsets
	# and look for "VPF0" signatures for image parts.
	
	var images: Array[Image] = []
	var visited_offsets: Dictionary = {}  # Tracks processed offsets
	var vpf_signature: PackedByteArray = PackedByteArray([0x56, 0x50, 0x46, 0x30])  # "VPF0"

	# **Read offsets from the header**
	var offsets: Array[int] = []
	var max_offset_read: int = 0x200 
	for i in range(0, max_offset_read, 4):
		var entry_offset: int = data.decode_u32(i)

		# **Skip invalid offsets** (0 or out of bounds)
		if entry_offset == 0 or entry_offset >= data.size():
			continue

		offsets.append(entry_offset)

	# **Sort and remove duplicates**
	offsets.sort()
	offsets = offsets.duplicate(false)  # Remove duplicate values

	# **Determine search range (stop scanning at first valid offset)**
	if offsets.is_empty():
		return images  # No valid offsets found
	var first_offset: int = offsets[0]  # Smallest offset found

	# **Process images at each unique offset**
	for offset in offsets:
		if offset >= data.size():  
			break  # **Stop processing beyond valid data size**
		if offset in visited_offsets:
			continue  # **Skip already processed offsets**

		visited_offsets[offset] = true  # **Mark offset as visited**

		# **Validate "VPF0" signature**
		if offset + 4 > data.size() or data.slice(offset, offset + 4) != vpf_signature:
			continue  # Skip invalid entries

		# **Read image header**
		var image_width: int = data.decode_u16(offset + 0xA)
		var image_height: int = data.decode_u16(offset + 0xC)
		var image_data_offset: int = data.decode_u16(offset + 0x10)  # Image data start
		var palette_offset: int = data.decode_u16(offset + 0x18)  # Palette data start
		if palette_offset == 0: # Assume RGB image if 0
			image_data_offset += offset
			var pixel_data: PackedByteArray = data.slice(image_data_offset, image_data_offset + image_width * image_height * 3)
			var image: Image = Image.create_from_data(image_width, image_height, false, Image.FORMAT_RGB8, pixel_data)
			images.append(image)
			continue
			
		image_data_offset += offset
		palette_offset += offset

		# **Ensure offsets are within bounds**
		if image_data_offset >= data.size() or palette_offset + 0x400 > data.size():
			continue  # Skip corrupted entries

		# **Extract and process palette (1024 bytes, 256 RGBA entries)**
		var palette: PackedByteArray = data.slice(palette_offset, palette_offset + 0x400)
		palette = ComFuncs.unswizzle_palette(palette, 32)

		#if remove_alpha:
			#for i in range(0, 0x400, 4):
				#palette.encode_u8(i + 3, 255)

		# **Extract raw pixel data**
		var pixel_data: PackedByteArray = data.slice(image_data_offset, image_data_offset + image_width * image_height)
		var image: Image = Image.create(image_width, image_height, false, Image.FORMAT_RGBA8)
		if remove_alpha:
			image = Image.create(image_width, image_height, false, Image.FORMAT_RGB8)
			
		for y in range(image_height):
			for x in range(image_width):
				var pixel_index: int = pixel_data[x + y * image_width]
				var r: int = palette[pixel_index * 4 + 0]
				var g: int = palette[pixel_index * 4 + 1]
				var b: int = palette[pixel_index * 4 + 2]
				var a: int = palette[pixel_index * 4 + 3]
				if remove_alpha:
					image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0))
				else:
					image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0))

		images.append(image)

	return images
	
	
func process_vpf_single_image(data: PackedByteArray) -> Image:
	var image_width: int = data.decode_u16(0xA)
	var image_height: int = data.decode_u16(0xC)
	var image_data_offset: int = data.decode_u16(0x10)
	var palette_offset: int = data.decode_u16(0x18)
	
	if palette_offset == 0: # Assume RGB image if 0
		var pixel_data: PackedByteArray = data.slice(image_data_offset, image_data_offset + image_width * image_height * 3)
		return Image.create_from_data(image_width, image_height, false, Image.FORMAT_RGB8, pixel_data)

	var palette: PackedByteArray = data.slice(palette_offset, palette_offset + 0x400)
	palette = ComFuncs.unswizzle_palette(palette, 32)

	#if remove_alpha:
		#for i in range(0, 0x400, 4):
			#palette.encode_u8(i + 3, 255)

	var pixel_data: PackedByteArray = data.slice(image_data_offset, image_data_offset + image_width * image_height)
	var image: Image = Image.create(image_width, image_height, false, Image.FORMAT_RGBA8)
	if remove_alpha:
		image = Image.create(image_width, image_height, false, Image.FORMAT_RGB8)

	for y in range(image_height):
		for x in range(image_width):
			var pixel_index: int = pixel_data[x + y * image_width]
			var r: int = palette[pixel_index * 4 + 0]
			var g: int = palette[pixel_index * 4 + 1]
			var b: int = palette[pixel_index * 4 + 2]
			var a: int = palette[pixel_index * 4 + 3]
			if remove_alpha:
				image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0))
			else:
				image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0))

	return image
	
	
func decrypt_rom_header(rom: PackedByteArray, xor_tbl: PackedByteArray) -> PackedByteArray:
	var word_1: int
	var word_2: int
	var off: int = 0x10
	
	while off < rom.size():
		word_1 = rom.decode_u32(off)
		word_2 = xor_tbl.decode_u32(off)
		rom.encode_u32(off, word_1 ^ word_2)
		off += 0x4
		
	return rom
	
	
func decrypt_rom_header_PIAGO(rom: PackedByteArray) -> PackedByteArray:
	 # Initialize constants
	var s2_offset_8: int = 0x0008
	var s2_offset_12: int = 0x000c
	var a2: int = 0x000343FD
	var t0: int = 0x00269EC3
	var result: PackedByteArray = rom.duplicate() # Create a copy to modify

	# Extract the number of iterations and starting values
	var total_iterations: int = (rom.decode_u32(s2_offset_8) << 11)
	var a1: int = rom.decode_u32(s2_offset_12)
	var a3: int = 0x0010  # Initial rom offset
	var s0: int = 0x0010  # Initial offset for data processing

	# Processing loop
	while a3 < total_iterations:
		# Multiply a1 by a2
		var mult_result: int = a1 * a2

		# Add t0 to the result
		a1 = (mult_result + t0) & 0xFFFFFFFF  # Keep within 32-bit range

		# Read a byte from the current position in the buffer
		var v0: int = result[s0]

		# Process XOR operations
		var v1: int = (a1 >> 16) ^ a1
		v0 = v0 ^ (v1 & 0xFF)

		# Write the modified byte back to the buffer
		result[s0] = v0

		# Increment pointers and counter
		s0 += 1
		a3 += 1

	return result
	
	
func decrypt_rom_header_PARFAIT(rom: PackedByteArray) -> PackedByteArray:
	var key: int = ~rom.decode_u32(0xC) & 0xFFFFFFFF
	for off in range(0x80, rom.size(), 4):
		var v0: int = rom.decode_u32(off)
		v0 ^= key
		rom.encode_s32(off, v0 & 0xFFFFFFFF)
		key = ~((key >> 17) | (key << 5)) & 0xFFFFFFFF
	
	return rom
	
	
func decrypt_int_PURECURE(key: int) -> PackedInt64Array:
	var v1: int = 0x000343FD  # Multiplier constant
	var v0: int = 0x00269EC3  # Addition constant
	var keys: PackedInt64Array # New keys to return.
	# keys[0] should be returned to this function for loops
	# keys[1] is xor'd by the input byte from a buffer needing decryption.
	
	var n_key_1: int = ((key * v1) + v0) & 0xFFFFFFFF
	var n_key_2: int = (n_key_1 >> 10) & 0xFFFF
	keys.append(n_key_1)
	keys.append(n_key_2)
	return keys
	
	
func decrypt_mem_file_PURECURE(input_buffer: PackedByteArray, sector_start: int) -> PackedByteArray:
	var sector_size: int = 0x800  # Size of each sector
	var block_size: int = 0x10  # Block size to decrypt
	var block_idx: int = 0 # Block index
	var total_blocks: int = input_buffer.size() # Total blocks to process
	var lookup_tbl_off: int = 0 # Table lookup offset
	
	while block_idx < total_blocks:
		var block_start: int = block_idx
		var block_end: int = block_start + block_size
		var sector: int = block_idx / sector_size
		
		var v1: int = sector_start + sector # Add sector start and current sector
		var keys: PackedInt64Array = decrypt_int_PURECURE(v1) # Current sector aligned to 0x800 becomes key
		lookup_tbl_off = keys[1] & 0x0FFF
		var lookup_idx: int = 0 # Resets every 0x10 bytes
		for a2 in range(block_start, block_end):
			if a2 >= total_blocks:
				return input_buffer
			lookup_tbl_off += lookup_idx
			var v0: int = input_buffer.decode_u8(a2)
			var a0: int = lookup_tbl.decode_u8(lookup_tbl_off)
			input_buffer.encode_s8(a2, (v0 ^ a0) & 0xFF)
			lookup_tbl_off += 1
			
		block_idx += sector_size
	
	
	return input_buffer
	
	
func decrypt_mem_file_PIAGO(input_buffer: PackedByteArray, decryption_key: int, sector_start: int) -> PackedByteArray:
	# Used by PIAGO encryption

	# Constants
	var t2: int = 0x000343FD  # Multiplier constant
	var t7: int = 0x00269EC3  # Addition constant
	var sector_size: int = 0x800  # Size of each sector
	var block_size: int = 0x10  # Block size to decrypt

	# Create a copy of the input buffer to modify
	var result: PackedByteArray = input_buffer.duplicate()
	var total_blocks: int = result.size()  # Total blocks to process

	# Decryption variables
	var a2: int = 0  # Block index
	var t4: int = decryption_key  # Global decryption key
	var t5: int = sector_start  # Sector start used as part of the key

	# Process each block
	while a2 < total_blocks:
		var block_start: int = a2
		var block_end: int = block_start + block_size
		var sector: int = a2 / sector_size
		
		var v0: int = t5 + sector # Add sector start and block index
		var a1: int = v0 + t4  # Add decryption key

		# First multiplication and addition
		v0 = a1 * t2  # Multiply by t2
		a1 = (v0 + t7) & 0xFFFFFFFF  # Add t7 and ensure 32-bit

		# Iterate over the first 0x10 bytes of the sector
		for a0 in range(block_start, block_end):
			if a0 >= total_blocks:
				return result
			# Second multiplication and addition
			v0 = a1 * t2  # Multiply by t2 again
			a1 = (v0 + t7) & 0xFFFFFFFF  # Add t7 and ensure 32-bit

			# Derive XOR value
			var v1: int = a1 ^ (a1 >> 16) # XOR derived from a1

			# Decrypt the current byte
			var current_byte: int = result[a0]
			result[a0] = (current_byte ^ v1) & 0xFF  # XOR with calculated value

		# Move to the next sector
		a2 += sector_size

	return result
	
	
func decompress_lzss_sneo(input_data: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray
	var v0: int
	var v1: int
	var a0: int
	var a1: int
	var a2: int
	var a3: int
	var t0: int 
	var t2: int
	
	a0 = 0 # Input header start
	a1 = 0 # Out offset
	a3 = input_data.decode_u32(0x8)
	out.resize(input_data.decode_u32(0x4))
	
	a0 += 0xC
	t0 = 2
	t2 = 1
	var goto: String = "001004AC"
	while true:
		match goto:
			"00100458":
				if v0 == 0:
					out.encode_s8(a1, a2)
					a1 += 1
					goto = "001004AC"
				else:
					v1 = input_data.decode_u8(a0)
					a3 -= 1
					a0 += 1
					v0 = v1 & 0xE0
					v0 <<= 3
					v1 &= 0x1F
					v0 = a2 + v0
					a2 = a1 - v0
					v1 += 2
					if v1 < 0:
						goto = "001004AC"
					else:
						while v1 >= 0:
							v0 = out.decode_u8(a2)
							v1 -= 1
							a2 += 1
							out.encode_s8(a1, v0)
							a1 += 1
						goto = "001004B0"
						if a0 >= input_data.size():
							return out
						a2 = input_data.decode_u8(a0)
			"001004AC":
				if a0 >= input_data.size():
					return out
				a2 = input_data.decode_u8(a0)
				goto = "001004B0"
			"001004B0":
				t0 >>= 1
				a0 += 1
				if t0 != t2:
					goto = "001004CC"
				else:
					t0 = a2 | 0x100
					a3 -= 1
					a2 = input_data.decode_u8(a0)
					a0 += 1
					goto = "001004CC"
			"001004CC":
				a3 -= 1
				v0 = t0 & 1
				if a3 >= 0:
					goto = "00100458"
				else:
					return out
	return out
	
	
func decompress_sneo(input: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray
	var v0: int
	var v1: int
	var a0: int
	var a1: int
	var a2: int # section start
	var a3: int
	var t0: int 
	var t1: int
	var t2: int
	var t3: int
	var t4: int
	var t5: int
	var t6: int
	var t7: int # out off
	var is_pic: bool = false # For Katakamuna
	var is_pic2: bool = false
	var is_bup: bool = false # For Katakamuna
	var is_bup2: bool = false
	var section_start: int
	var section_end: int
	var num_img_parts: int
	var part_width: int
	var part_height: int
	var img_part: int
	var imgs: Array[PackedByteArray]
	
	var hdr_bytes: PackedByteArray = input.slice(0, 4)
	var hdr_str: String = hdr_bytes.get_string_from_ascii()
	if hdr_str == "LZS2":
		section_start = 0x10
		section_end = input.decode_u32(0x8)
		out.resize(section_end)
		a2 = section_start
		a3 = section_end
	elif hdr_str == "LZSS":
		out = ComFuncs.decompLZSS(input.slice(0x10), input.size() - 0x10, input.decode_u32(4) - 0x10)
		return out
	elif hdr_str == "BUP2":
		# There's a bunch of data in the headers still, this only semi works.
		is_bup2 = true
		section_start = input.decode_u32(0x1C)
		section_end = input.decode_u32(0x8)
		out.resize(input.decode_u16(0x14) * input.decode_u16(0x16))
		a2 = section_start
		a3 = section_end
	elif hdr_str == "PIC2":
		is_pic2 = true
		img_part = 0
		var section: int = (img_part * 0x10) + 0x20
		num_img_parts = input.decode_u32(0x1C)
		# Dummy images in Yoake Mae Yori Ruriiro na: Brighter than Dawning Blue
		if num_img_parts == 0:
			return PackedByteArray()
		section_start = input.decode_u32(0x28)
		section_end = input.decode_u32(0x2C)
		part_width = input.decode_u16(0x24)
		part_height = input.decode_u16(0x26)
		# Append image parts from input if image part size is 0.
		if section_end == 0:
			while section_end == 0:
				section_end = (part_width * part_height) + section_start
				out = input.slice(section_start, section_end)
				imgs.append(PackedByteArray(out))
				out.clear()
				img_part += 1
				if img_part == num_img_parts:
					section_start = input.decode_u32(0x18)
					section_end = input.decode_u32(0x28)
					out.append_array(input.slice(0, section_end))
					for img in range(0, imgs.size()):
						out.append_array(imgs[img])
					return out
				section = (img_part * 0x10) + 0x20
				section_start = input.decode_u32(section + 0x08)
				section_end = input.decode_u32(section + 0x0C)
				part_width = input.decode_u16(section + 0x04)
				part_height = input.decode_u16(section + 0x06)
		out.resize(part_width * part_height)
		a2 = section_start
		a3 = section_end
	elif "PIC ":
		is_pic = true
		section_start = input.decode_u32(0x20)
		section_end = input.decode_u32(input.size() - 0x20)
		part_width = input.decode_u16(0x04)
		part_height = input.decode_u16(0x06)
		out.resize(part_width * part_height)
	
	var goto: String = "init" # 001352C0 based on Kono Aozora Ni
	while true:
		match goto:
			"init":
				t4 = 0
				t1 = 0
				v0 = a2 + t4
				if a3 == 0:
					goto = "img_chk"
				else:
					goto = "001352D8"
			"001352D8":
				t0 = 0
				if v0 >= input.size():
					goto ="img_chk"
					#break
				else:
					a1 = input.decode_u8(v0)
					t4 += 1
					goto = "001352E8"
			"001352E8":
				v0 = a1 ^ 1
				v0 &= 1
				if v0 == 0:
					v0 = t4 < a3
					goto = "00135328"
				else:
					v0 = t4 < a3
					if v0 == 0:
						v0 = t1
						goto = "img_chk"
					else:
						v0 = a2 + t4
						a0 = t7 + t1
						if v0 >= input.size() or a0 >= out.size():
							goto = "img_chk"
							#break
						else:
							v1 = input.decode_u8(v0)
							t6 = a1 >> 1
							t5 = t0 + 1
							t4 += 1
							out.encode_s8(a0, v1) # a0
							goto = "00135398"
							t1 += 1
			"00135328":
				v1 = t4 + 2
				v0 = a3 < v1
				if v0 != 0:
					v0 = t1
					goto = "img_chk"
				else:
					v0 = a2 + t4
					if v0 >= input.size():
						goto = "img_chk"
						#break
					else:
						t6 = a1 >> 1
						a0 = input.decode_u8(v0)
						t4 = v1
						v1 = input.decode_u8(v0 + 1)
						t5 = t0 + 1
						v0 = a0 & 0xF0
						t3 = t7 + t1
						v0 <<= 4
						a0 &= 0xF
						v1 = ~(v1 | v0)
						t0 = a0 + 3
						v1 = (v1 + t1)
						a1 = 0
						if t0 == 0:
							t2 = t7 + v1
							goto = "00135394"
						else:
							t2 = t7 + v1
							v0 = 1
							while v0 != 0:
								v0 = t2 + a1
								a0 = t3 + a1
								if v0 >= out.size() or a0 >= out.size():
									goto = "img_chk"
									break
								else:
									v1 = out.decode_u8(v0) # v0
									a1 += 1
									v0 = a1 < t0
									out.encode_s8(a0, v1)
							goto = "00135394"
			"00135394":
				t1 += t0
				goto = "00135398"
			"00135398":
				t0 = t5
				v0 = t0 < 8
				a1 = t6
				if v0 != 0:
					goto = "001352E8"
				else:
					a1 = t6
					v0 = t4 < a3
					if v0 != 0:
						goto = "001352D8"
						v0 = a2 + t4
					else:
						v0 = a2 + t4
						v0 = t1
						goto = "img_chk"
			"img_chk":
				if is_pic2:
					img_part += 1
					imgs.append(PackedByteArray(out))
					out.clear()
					
					var section: int = (img_part * 0x10) + 0x20
					if img_part != num_img_parts:
						part_width = input.decode_u16(section + 0x04)
						part_height = input.decode_u16(section + 0x06)
						section_start = input.decode_u32(section + 0x08)
						section_end = input.decode_u32(section + 0x0C)
						if section_end == 0:
							while section_end == 0:
								section_end = (part_width * part_height) + section_start
								out = input.slice(section_start, section_end)
								imgs.append(PackedByteArray(out))
								out.clear()
								img_part += 1
								if img_part == num_img_parts:
									section_start = input.decode_u32(0x18)
									section_end = input.decode_u32(0x28)
									out.append_array(input.slice(0, section_end))
									for img in range(0, imgs.size()):
										out.append_array(imgs[img])
									return out
								section = (img_part * 0x10) + 0x20
								section_start = input.decode_u32(section + 0x08)
								section_end = input.decode_u32(section + 0x0C)
								part_width = input.decode_u16(section + 0x04)
								part_height = input.decode_u16(section + 0x06)
							
						out.resize(part_width * part_height)
						a2 = section_start
						a3 = section_end
						goto = "init"
					else:
						# Append palette then image parts
						section_start = input.decode_u32(0x18)
						section_end = input.decode_u32(0x28)
						out.append_array(input.slice(0, section_end))
						for img in range(0, imgs.size()):
							out.append_array(imgs[img])
						break
				elif is_bup2:
					imgs.append(PackedByteArray(out))
					out.clear()
					
					section_end = input.decode_u32(0x1C)
					out.append_array(input.slice(0, section_end))
					out.append_array(imgs[0])
					break
				elif is_pic:
					imgs.append(PackedByteArray(out))
					out.clear()
					# Append palette then image parts
					section_start = input.decode_u32(0xC)
					section_end = input.decode_u32(0x10)
					out.append_array(input.slice(0, section_end))
					for img in range(0, imgs.size()):
						out.append_array(imgs[img])
					break
				else:
					break
		
	return out
#func make_xor_table():
	## Not needed. Seems to be for a CRC check
	#var table = PackedByteArray()
	#var a1 = 0
	## var a3 = 0x1F6F10  # Base address for the table in memory (kono aozora)
#
	## Outer loop
	#while a1 < 0x100:  # Loop until a1 reaches 256
		#var v1 = 0
		#var a0 = 0x80  # Starting bit
#
		## Inner loop
		#while a0 > 0:
			#if a1 & a0 != 0:
				#v1 ^= 0x8000
#
			#var v0 = v1 & 0x8000
			#if v0 != 0:
				#v0 = (v1 << 1) & 0xFFFF
				#v1 = v0 ^ 0x1021
			#else:
				#v1 = (v1 << 1) & 0xFFFF
#
			#a0 >>= 1
#
		## Store result into the table
		#table.append(v1 & 0xFF)  # Store lower byte
		#table.append((v1 >> 8) & 0xFF)  # Store higher byte
#
		#a1 += 1
	#
	#xor_table = table
	#return


func _on_load_iso_pressed() -> void:
	file_load_iso.show()


func _on_file_load_iso_file_selected(path: String) -> void:
	selected_file = path
	chose_file = true
	file_load_folder.show()


func _on_file_load_folder_dir_selected(dir: String) -> void:
	folder_path = dir
	chose_folder = true


func _on_output_debug_toggled(_toggled_on: bool) -> void:
	debug_out = !debug_out


func _on_remove_alpha_toggled(_toggled_on: bool) -> void:
	remove_alpha = !remove_alpha


func _on_output_decrypted_toggled(_toggled_on: bool) -> void:
	debug_raw_out = !debug_raw_out


func _on_remove_bup_alpha_toggled(_toggled_on: bool) -> void:
	remove_alpha_bup = !remove_alpha_bup
