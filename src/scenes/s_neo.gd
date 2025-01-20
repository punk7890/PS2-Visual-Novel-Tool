extends Control

@onready var file_load_iso: FileDialog = $FILELoadISO
@onready var file_load_folder: FileDialog = $FILELoadFOLDER

var folder_path: String
var selected_file: String = ""
var chose_file: bool = false
var chose_folder: bool = false
var debug_out: bool = false
var debug_raw_out: bool = false
var remove_alpha: bool = true

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
	var xor_file: FileAccess
	var fail: bool = false
	var expected_str: String
	var hdr_string: String
	var rom_off: int
	var rom_size: int
	var buff: PackedByteArray
	var xor_tbl: PackedByteArray
	var num_files: int
	var f_name: String = "dummy"
	var f_name_off: int
	var last_name_pos: int
	var last_tbl_pos: int
	var f_offset: int
	var f_size: int
	var file_tbl: int
	var pos: int
	
	# TODO: There's a lot of encrypted data before ROM start, but it seems not needed? What is it all?
	# Some small images don't output correctly. Appears to be a process_pic2ps2_image problem.
	# Check whatever is in .lzs files as I haven't fully verified if the data is correct.
	# Need a Shift-JIS decoder to UTF-8 for file names
	
	in_file = FileAccess.open(selected_file, FileAccess.READ)
	# Check if DVD name matches
	if Main.game_type == Main.KONOAOZORA:
		in_file.seek(0x83071)
		var hdr_bytes: PackedByteArray = in_file.get_buffer(8)
		hdr_string = hdr_bytes.get_string_from_ascii()
		expected_str = "KONNYAKU"
		if hdr_string == expected_str:
			rom_off = 0x445C0 # At 0x00135684 in memory inside a function
		else:
			fail = true
			
	if fail:
		OS.alert("%s doesn't match known offset! Expected %s but got %s." % [selected_file, expected_str, hdr_string])
		return
			
	rom_off *= 0x800
	
	in_file.seek(rom_off + 8)
	rom_size = in_file.get_32()
	rom_size *= 0x800
	
	in_file.seek(rom_off)
	buff = in_file.get_buffer(rom_size)
	# Xor table is after ROM offset with the same size
	xor_tbl = in_file.get_buffer(rom_size)
	
	buff = decryptRomHeader(buff, xor_tbl)
	
	out_file = FileAccess.open(folder_path + "/!ROM.BIN", FileAccess.WRITE)
	out_file.store_buffer(buff)
	out_file.close()
	buff.clear()
	
	xor_file = FileAccess.open(folder_path + "/!ROM.BIN", FileAccess.READ)
	
	pos = 0x10
	while pos < rom_size:
		xor_file.seek(pos)
		if xor_file.eof_reached():
			break
			
		file_tbl = pos
		num_files = xor_file.get_32()
		if num_files == 0:
			break
		last_tbl_pos = xor_file.get_position()
		for file in num_files:
			xor_file.seek(last_tbl_pos)
			f_name_off = xor_file.get_32() # if highest 32 bit is 0x80, appears to be a folder or sometimes nothing (0x2E)
			f_offset = xor_file.get_32()
			f_offset = (f_offset * 0x800) + rom_off
			f_size = xor_file.get_32()
			last_tbl_pos = xor_file.get_position()
			if f_name_off > 0x7FFFFFFF:
				# Skip folders as I am unsure how they are sorted
				xor_file.seek(file_tbl + f_name_off & 0x7FFFFFFF)
				f_name = xor_file.get_line()
				last_name_pos = xor_file.get_position()
				if !last_name_pos % 16 == 0:
					last_name_pos = (last_name_pos + 15) & ~15
				continue
			
			
			xor_file.seek(file_tbl + f_name_off)
			f_name = xor_file.get_line()
			last_name_pos = xor_file.get_position()
					
			# Skip music names for now as they have Shift-JIS names which cause Godot to die.
			if f_name.get_extension() == "ads":
				if !last_name_pos % 16 == 0:
					last_name_pos = (last_name_pos + 15) & ~15
				continue
			# Use for debugging a certain file
			#if f_name.get_extension() != "pic":
				#if !last_name_pos % 16 == 0:
					#last_name_pos = (last_name_pos + 15) & ~15
				#continue
			
			in_file.seek(f_offset)
			buff = in_file.get_buffer(f_size)
			# Decrypt bytes in sectors
			var dec_pos: int = 0
			while dec_pos < f_size:
				for i in range(0, 0x10):
					if dec_pos + i >= f_size:
						break
					var bytes: int = buff.decode_u8(dec_pos + i)
					buff.encode_u8(dec_pos + i, bytes ^ 0xFF)
				dec_pos += 0x800
				
			if !last_name_pos % 16 == 0: # Align to 0x10 boundary for next table start when i reaches num_files
				last_name_pos = (last_name_pos + 15) & ~15
				
			if debug_out:
				out_file = FileAccess.open(folder_path + "/%s" % f_name + ".ORG", FileAccess.WRITE)
				out_file.store_buffer(buff)
				out_file.close()
			
			# Decompression ONLY for lzr files and .pic?
			if f_name.get_extension() == "pic" or f_name.get_extension() == "lzs":
				buff = decompress(buff)
				
			var hdr_bytes: PackedByteArray = buff.slice(0, 4)
			var hdr_str: String = hdr_bytes.get_string_from_ascii()
			if hdr_str == "PIC2":
				if debug_raw_out:
					out_file = FileAccess.open(folder_path + "/%s" % f_name + ".DEC", FileAccess.WRITE)
					out_file.store_buffer(buff)
					out_file.close()
				
				var png: Image = process_pic2ps2_image(buff)
				png.save_png(folder_path + "/%s" % f_name + ".PNG")
				
				print("0x%08X " % f_offset, "0x%08X " % f_size, "%s" % folder_path + "/%s " % f_name)
				continue
				
			out_file = FileAccess.open(folder_path + "/%s" % f_name, FileAccess.WRITE)
			out_file.store_buffer(buff)
			out_file.close()
			
			print("0x%08X " % f_offset, "0x%08X " % f_size, "%s" % folder_path + "/%s " % f_name)
		
		pos = last_name_pos
			
	print_rich("[color=green]Finished![/color]")
	
	
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
	if remove_alpha:
		for i in range(0, 0x400, 4):
			palette.encode_u8(i + 3, 255)

	# Create the final image with a size large enough to fit all parts
	var final_image: Image = Image.create(final_width, final_height, false, Image.FORMAT_RGBA8)

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
						tile_image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0))
				
				# Test tile
				# tile_image.save_png(folder_path + "/%02d" % i + ".PNG")
				# Place the tile into the final image at the correct position
				for y in range(tile_height):
					for x in range(tile_width):
						var pixel: Color = tile_image.get_pixel(x, y)
						final_image.set_pixel(part_x + tile_offset_x + x, part_y + tile_offset_y + y, pixel)

		# Update part info offset for the next part
		part_info_offset += 0x10

	return final_image
	
	
func decryptRomHeader(rom: PackedByteArray, xor_tbl: PackedByteArray) -> PackedByteArray:
	var word_1: int
	var word_2: int
	var off: int = 0x10
	
	while off < rom.size():
		word_1 = rom.decode_u32(off)
		word_2 = xor_tbl.decode_u32(off)
		rom.encode_u32(off, word_1 ^ word_2)
		off += 0x4
		
	return rom
	
	
func decompress(input: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray
	var v0:int
	var v1:int
	var a0:int
	var a1:int
	var a2:int # section start
	var a3:int
	var t0:int 
	var t1:int
	var t2:int
	var t3:int
	var t4:int
	var t5:int
	var t6:int
	var t7:int # out off
	var t8:int
	var t9: int
	var s1: int
	var s2: int
	var is_image: bool = false
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
		is_image = false
		section_start = 0x10
		section_end = input.decode_u32(0x8)
		out.resize(section_end)
		a2 = section_start
		a3 = section_end
	elif hdr_str == "PIC2":
		is_image = true
		img_part = 0
		num_img_parts = input.decode_u32(0x1C)
		section_start = input.decode_u32(0x28)
		section_end = input.decode_u32(0x2C)
		part_width = input.decode_u16(0x24)
		part_height = input.decode_u16(0x26)
		out.resize(part_width * part_height)
		a2 = section_start
		a3 = section_end
	
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
				if is_image:
					img_part += 1
					imgs.append(PackedByteArray(out))
					out.clear()
					
					var section: int = (img_part * 0x10) + 0x20
					if img_part != num_img_parts:
						part_width = input.decode_u16(section + 0x04)
						part_height = input.decode_u16(section + 0x06)
						section_start = input.decode_u32(section + 0x08)
						section_end = input.decode_u32(section + 0x0C)
						a2 = section_start
						a3 = section_end
						out.resize(part_width * part_height)
						goto = "init"
					else:
						# Append palette then image parts
						section_start = input.decode_u32(0x18)
						section_end = input.decode_u32(0x28)
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
	remove_alpha != remove_alpha


func _on_output_decrypted_toggled(_toggled_on: bool) -> void:
	debug_raw_out = !debug_raw_out