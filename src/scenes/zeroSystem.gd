extends Control

@onready var zero_load_exe: FileDialog = $ZEROLoadEXE
@onready var zero_load_pac: FileDialog = $ZEROLoadPAC
@onready var zero_load_folder: FileDialog = $ZEROLoadFOLDER
@onready var zero_load_tex: FileDialog = $ZEROLoadTEX
@onready var load_tex: Button = $HBoxContainer/LoadTEX

var exe_path: String
var folder_path:String
var selected_file: String
var selected_texs: PackedStringArray


func _ready() -> void:
	zero_load_exe.filters = [
	"SLPM_666.18,
	SLPM_669.42,SLPM_669.43,
	SLPM_656.07, SLPM_656.08,
	SLPM_656.71,
	SLPS_257.19,
	SLPM_659.68, SLPM_659.69,
	SLPM_664.40,
	SLPM_550.70, SLPM_550.71,
	SLPM_667.32, SLPM_667.33,
	SLPM_659.65,
	SLPS_256.70,
	SLPM_666.25,
	SLPM_663.76,
	SLPM_665.08,
	SLPM_668.60"]
	
	if Main.game_type != Main.OTONANOGALJAN2:
		load_tex.hide()
	

func _process(_delta: float) -> void:
	if selected_file and folder_path:
		extractBin()
		selected_file = ""
		folder_path = ""
	elif selected_texs and folder_path:
		convert_tex()
		selected_texs
		folder_path = ""
		
		
func extractBin() -> void:
	var f_name: String
	var hash1: int
	var hash2: int
	var offset: int
	var exe_start: int
	var exe_file: FileAccess
	var in_file: FileAccess
	var out_file: FileAccess
	var f_size: int
	var id: int
	var null_byte: int
	var null_32: int
	var type: int
	var buff: PackedByteArray
	var is_pac_bin: bool
	
	if selected_file.get_file() == "PAC.BIN":
		is_pac_bin = true
	elif selected_file.ends_with(".PAC"):
		is_pac_bin = false
	
	match is_pac_bin:
		true:
			if exe_path == "":
				OS.alert("Load an EXE (SLPM_XXX.XX) first.")
				return
				
			if exe_path.get_file() == "SLPM_666.18": # Yumemishi
				exe_start = 0xBB9E0
			elif exe_path.get_file() == "SLPM_669.42" or exe_path.get_file() == "SLPM_669.43": # Final Approach 2 - 1st Priority
				exe_start = 0xBDCD8
			elif exe_path.get_file() == "SLPM_656.07" or exe_path.get_file() == "SLPM_656.08": # 3LDK - Shiawase ni Narouyo
				exe_start = 0x91200
			elif exe_path.get_file() == "SLPM_656.71": # Double Wish
				exe_start = 0x9C940
			elif  exe_path.get_file() == "SLPS_257.19": # Happiness! De-Lucks
				exe_start = 0xF92B8
			elif exe_path.get_file() == "SLPM_659.68" or exe_path.get_file() == "SLPM_659.69": # Love Doll: Lovely Idol
				exe_start = 0xB0D48
			elif exe_path.get_file() == "SLPM_664.40": # Hokenshitsu he Youkoso
				exe_start = 0xADC10
			elif exe_path.get_file() == "SLPM_550.70" or exe_path.get_file() == "SLPM_550.71": # Yumemi Hakusho: Second Dream
				exe_start = 0xBBA48
			elif exe_path.get_file() == "SLPM_667.32" or exe_path.get_file() == "SLPM_667.33": # Iinazuke
				exe_start = 0xC0418
			elif exe_path.get_file() == "SLPM_659.65": # Magical Tale: Chiicha na Mahoutsukai
				exe_start = 0x9E658
			elif exe_path.get_file() == "SLPS_256.70": # School Rumble Ni-Gakki
				exe_start = 0xB7790
			elif exe_path.get_file() == "SLPM_666.25": # Trouble Fortune Company:  Happy Cure
				exe_start = 0xC3E60
			elif exe_path.get_file() == "SLPM_663.76": # KimiSuta: Kimi to Study
				exe_start = 0xB14F8
			elif exe_path.get_file() == "SLPM_665.08": # Otome no Jijou
				exe_start = 0xBEC78
			elif exe_path.get_file() == "SLPM_668.60": # Nettai Teikiatsu Shoujo
				exe_start = 0xBB6C0
			else:
				OS.alert("Unknown EXE found.")
				return
			
			exe_file = FileAccess.open(exe_path, FileAccess.READ)
			in_file = FileAccess.open(selected_file, FileAccess.READ)
			exe_file.seek(exe_start)
			while true:
				hash1 = exe_file.get_32()
				hash2 = exe_file.get_32()
				offset = exe_file.get_32() * 0x800
				f_size = exe_file.get_32()
				null_byte = exe_file.get_8()
				type = exe_file.get_8()
				id = exe_file.get_16()
				null_32 = exe_file.get_32()
				
				if f_size < 0 or f_size == 0xFFFFFFFF:
					break
				
				in_file.seek(offset)
				buff = in_file.get_buffer(f_size)
				
				if buff.slice(0, 3).get_string_from_ascii() == "LZS":
					f_size = buff.decode_u32(4)
					buff = ComFuncs.decompLZSS(buff.slice(8), buff.size() - 8, f_size, 0xFEE, 0x20)
					
				if type == 0x0A:
					f_name = "MOV%05d.PSS" % id
				elif type == 0x0C:
					f_name = "ANM%05d.BIN" % id
				elif type == 0xFA:
					var num: int = 0
					var i: int = 0
					var tak_data_start: int = buff.decode_u32(0)
					var tak_data_comp_size: int = buff.decode_u32(4)
					
					while tak_data_start != tak_data_comp_size:
						if buff.slice(tak_data_start, tak_data_start + 3).get_string_from_ascii() == "LZS":
							var tak_data: PackedByteArray = (PackedByteArray(buff.slice(tak_data_start, tak_data_start + tak_data_comp_size)))
							var tak_decomp_size: int = tak_data.decode_u32(4)
							tak_data = ComFuncs.decompLZSS(tak_data.slice(8), tak_data_comp_size, tak_decomp_size)
							
							if tak_data.slice(0, 4).get_string_from_ascii() == "TIM2":
								f_name = "TAK%05d_%02d.TM2" % [id, num]
								var pngs: Array[Image]
								if Main.game_type == Main.SCHOOLRUMBLENI:
									pngs = load_tim2_images_mod(tak_data, false)
								else:
									pngs = ComFuncs.load_tim2_images(tak_data, false, true)
									
								for p in range(pngs.size()):
									var png: Image = pngs[p]
									png.save_png(folder_path + "/%s" % f_name + "_%04d.PNG" %  p)
							else:
								f_name = "TAK%05d_%02d.BIN" % [id, num]
								
							out_file = FileAccess.open(folder_path + "/%s" % f_name, FileAccess.WRITE)
							out_file.store_buffer(tak_data)
							out_file.close()
							tak_data.clear()
							i += 0xC
							num += 1
						else:
							var tak_data: PackedByteArray = (PackedByteArray(buff.slice(tak_data_start, tak_data_start + tak_data_comp_size)))
							
							f_name = "TAK%05d_%02d.BIN" % [id, num]
							out_file = FileAccess.open(folder_path + "/%s" % f_name, FileAccess.WRITE)
							out_file.store_buffer(tak_data)
							out_file.close()
							tak_data.clear()
							i += 0xC
							num += 1
						print("%08X %08X %s/%s" % [tak_data_start, tak_data_comp_size, folder_path, f_name])
						tak_data_start = buff.decode_u32(i)
						tak_data_comp_size = buff.decode_u32(i + 4)
					f_name = "TAK%05d.BIN" % id
				elif type == 0x01:
					f_name = "VIS%05d.TM2" % id
					var pngs: Array[Image]
					if Main.game_type == Main.SCHOOLRUMBLENI:
						pngs = load_tim2_images_mod(buff, false)
					else:
						pngs = ComFuncs.load_tim2_images(buff, false, true)
						
					for p in range(pngs.size()):
						var png: Image = pngs[p]
						png.save_png(folder_path + "/%s" % f_name + "_%04d.PNG" %  p)
				elif type == 0x02:
					f_name = "STR%05d.VGS" % id
				elif type == 0x06:
					f_name = "_SE%05d.HBD" % id
				elif type == 0x08:
					f_name = "VCE%05d.HBD" % id
				elif type == 0x10:
						var arr: Array = upac_parse(buff)
						if arr[0]:
							f_name = "SRE%05d.TM2" % id
							f_size = arr[1]
							buff = arr[2]
							
							var pngs: Array[Image]
							if Main.game_type == Main.SCHOOLRUMBLENI:
								pngs = load_tim2_images_mod(buff, false)
							else:
								pngs = ComFuncs.load_tim2_images(buff, false, true)
								
							for p in range(pngs.size()):
								var png: Image = pngs[p]
								png.save_png(folder_path + "/%s" % f_name + "_%04d.PNG" %  p)
						else:
							f_name = "SRE%05d.BIN" % id
							if arr[1] != 0:
								f_size = arr[1]
								buff = arr[2]
				elif type == 0xFF:
					f_name = "DMY%05d.BIN" % id
				elif type == 0x67:
					f_name = "FNT%05d.BIN" % id
				else:
					f_name = "UNK%05d.BIN" % id
					
				
				out_file = FileAccess.open(folder_path + "/%s" % f_name, FileAccess.WRITE)
				out_file.store_buffer(buff)
				out_file.close()
				
				buff.clear()
				
				print("%08X %08X %02X %s/%s" % [offset, f_size, type, folder_path, f_name])
				
		false:
			if Main.game_type == Main.NATSUIROSUNADOKEI:
				var f_ext: String
				
				in_file = FileAccess.open(selected_file, FileAccess.READ)
				var pac_hed: FileAccess = FileAccess.open(selected_file.get_basename() + ".HED", FileAccess.READ)
				if pac_hed == null:
					OS.alert("Couldn't find .HED file for %s!" % selected_file)
					return
					
				var unk_32: int = pac_hed.get_32()
				var next_pos: int = pac_hed.get_position()
				while pac_hed.get_position() < pac_hed.get_length():
					pac_hed.seek(next_pos)
					offset = pac_hed.get_32()
					f_size = pac_hed.get_32()
					var f_id: int = pac_hed.get_32()
					
					next_pos = pac_hed.get_position()
					if pac_hed.eof_reached():
						break
					
					in_file.seek(offset)
					buff = in_file.get_buffer(f_size)
					
					if buff.slice(0, 4).get_string_from_ascii() == "TIM2":
						f_ext = ".TM2"
					elif buff.slice(0, 4).get_string_from_ascii() == "IECS":
						f_ext = ".HBD"
					else:
						f_ext = ".BIN"
					
					f_name = "/%08d" % f_id + f_ext
					
					if buff.slice(0, 4).get_string_from_ascii() == "TIM2":
						var pngs: Array[Image] = ComFuncs.load_tim2_images(buff, false, true)
						for i in range(pngs.size()):
							var png: Image = pngs[i]
							png.save_png(folder_path + "/%s" % f_name + "_%04d.PNG" %  i)
							
					out_file = FileAccess.open(folder_path + "%s" % f_name, FileAccess.WRITE)
					out_file.store_buffer(buff)
					out_file.close()
					
					buff.clear()
					
					print("%08X %08X %s%s" % [offset, f_size, folder_path, f_name])
			elif Main.game_type == Main.SORAIROFUUKIN:
				in_file = FileAccess.open(selected_file, FileAccess.READ)
				
				var num_files: int = in_file.get_32()
				var file_tbl: int = in_file.get_32()
				
				for files in range(0, num_files):
					in_file.seek((files * 0x20) + file_tbl)
					f_name = in_file.get_buffer(0x14).get_string_from_ascii()
					f_size = in_file.get_32()
					offset = in_file.get_32()
					var unk32: int = in_file.get_32()
					
					print("%08X %08X %s/%s" % [offset, f_size, folder_path, f_name])
					
					in_file.seek(offset)
					buff = in_file.get_buffer(f_size)
					
					if buff.slice(0, 3).get_string_from_ascii() == "LZS":
						f_size = buff.decode_u32(4)
						buff = ComFuncs.decompLZSS(buff.slice(8), buff.size() - 8, f_size)
						
					if buff.slice(0, 4).get_string_from_ascii() == "TIM2":
						var pngs: Array[Image] = ComFuncs.load_tim2_images(buff, false, true)
						for i in range(pngs.size()):
							var png: Image = pngs[i]
							png.save_png(folder_path + "/%s" % f_name + "_%04d.PNG" %  i)
							
					out_file = FileAccess.open(folder_path + "/%s" % f_name, FileAccess.WRITE)
					out_file.store_buffer(buff)
					out_file.close()
					
					buff.clear()
			else:
				in_file = FileAccess.open(selected_file, FileAccess.READ)
				
				if in_file.get_buffer(4).get_string_from_ascii() != "PAC":
					OS.alert("Invalid PAC header.")
					return
					
				var name_tbl_off: int = in_file.get_32()
				var num_files: int = in_file.get_32()
				var file_tbl: int = in_file.get_position()
				
				for files in range(0, num_files):
					in_file.seek((files * 8) + file_tbl)
					offset = in_file.get_32()
					f_size = in_file.get_32()
					
					in_file.seek((files * 0x40) + name_tbl_off)
					f_name = in_file.get_line()
					
					in_file.seek(offset)
					buff = in_file.get_buffer(f_size)
					
					if buff.slice(0, 3).get_string_from_ascii() == "LZS":
						f_size = buff.decode_u32(4)
						buff = ComFuncs.decompLZSS(buff.slice(8), buff.size() - 8, f_size, 0xFEE, 0x20)
						
					if buff.slice(0, 4).get_string_from_ascii() == "TIM2":
						var pngs: Array[Image] = ComFuncs.load_tim2_images(buff, false, true)
						for i in range(pngs.size()):
							var png: Image = pngs[i]
							png.save_png(folder_path + "/%s" % f_name + "_%04d.PNG" %  i)
							
					out_file = FileAccess.open(folder_path + "/%s" % f_name, FileAccess.WRITE)
					out_file.store_buffer(buff)
					out_file.close()
					
					if Main.game_type != Main.KIMIGANOZOMUEIEN and f_name.get_extension() == "ext":
						var png: Image = make_ext_img(buff)
						png.save_png(folder_path + "/%s" % f_name + ".PNG")
					
					buff.clear()
					
					print("%08X %08X %s/%s" % [offset, f_size, folder_path, f_name])
				
	print_rich("[color=green]Finished![/color]")
	
	
func convert_tex() -> void:
	for file: int in selected_texs.size():
		var in_file: FileAccess = FileAccess.open(selected_texs[file], FileAccess.READ)
		var arc_name: String = selected_texs[file].get_file().get_basename()
		
		var buff: PackedByteArray = in_file.get_buffer(in_file.get_length())
		var f_size: int
		if buff.slice(0, 3).get_string_from_ascii() == "LZS":
			f_size = buff.decode_u32(4)
			buff = ComFuncs.decompLZSS(buff.slice(8), buff.size() - 8, f_size)
		
			var out_file: FileAccess = FileAccess.open(folder_path + "/%s" % arc_name + ".DEC", FileAccess.WRITE)
			out_file.store_buffer(buff)
		
		if buff.slice(0, 3).get_string_from_ascii() == "TEX":
			var name_tbl: int = buff.decode_u32(12)
			var num_files: int = buff.decode_u32(name_tbl)
			var pos: int = 0x14
			for i in range(num_files):
				var f_off: int = buff.decode_u32(pos)
				f_size = buff.decode_u32(pos + 4)
				var f_name: String = buff.slice(name_tbl + 4, name_tbl + 0x20).get_string_from_ascii()
				
				var png: Image = make_ext_img(buff.slice(f_off, f_size + f_off))
				png.save_png(folder_path + "/%s" % f_name + ".PNG")
				
				print("%08X %08X %s" %[f_off, f_size, folder_path + "/%s" % f_name + ".PNG"])
				
				pos += 8
				name_tbl += 0x40
	print_rich("[color=green]Finished![/color]")
	
	
func make_ext_img(data: PackedByteArray) -> Image:
	var type: int = data.decode_u32(4)
	if type not in [3, 8, 9]:
		push_error("Unknown image type: %08X" % type)
		return Image.create_empty(1, 1, false, Image.FORMAT_L8)
		
	var pal: PackedByteArray
	var img_dat: PackedByteArray
	var w: int = data.decode_u16(0x41C)
	var h: int = data.decode_u16(0x41E)
	if type == 3:
		w = data.decode_u16(0x10)
		h = data.decode_u16(0x12)
		var img_size: int = data.decode_u32(8) + 4
		img_dat = data.slice(0x14, img_size)
		for j in range(3, img_dat.size(), 4):
			var a: int = int((img_dat.decode_u8(j) / 128.0) * 255.0)
			img_dat.encode_u8(j, a)
		return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, img_dat)
	elif type == 8:
		w = data.decode_u16(0x5C)
		h = data.decode_u16(0x5E)

		# Palette: 0x40 bytes = 16 entries
		pal = data.slice(0x14, 0x54)

		# Fix alpha scaling
		for i in range(3, pal.size(), 4):
			var a: int = pal.decode_u8(i)
			pal.encode_u8(i, int((a / 128.0) * 255.0))

		# Image data starts at 0x60
		img_dat = data.slice(0x60)

		var image: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)

		for y in range(h):
			for x in range(0, w, 2):  # 2 pixels per byte
				var byte_index: int = (x + y * w) / 2
				var byte_value: int = img_dat[byte_index]

				var pixel_index_1 = byte_value & 0xF  # Low nibble (left pixel)
				var pixel_index_2 = (byte_value >> 4) & 0xF  # High nibble (right pixel)

				# Clamp to palette size (safety)
				pixel_index_1 = clamp(pixel_index_1, 0, 15)
				pixel_index_2 = clamp(pixel_index_2, 0, 15)

				# Left pixel
				var r1: int = pal[pixel_index_1 * 4 + 0]
				var g1: int = pal[pixel_index_1 * 4 + 1]
				var b1: int = pal[pixel_index_1 * 4 + 2]
				var a1: int = pal[pixel_index_1 * 4 + 3]
				image.set_pixel(x, y, Color(r1 / 255.0, g1 / 255.0, b1 / 255.0, a1 / 255.0))

				# Right pixel (if within width)
				if x + 1 < w:
					var r2: int = pal[pixel_index_2 * 4 + 0]
					var g2: int = pal[pixel_index_2 * 4 + 1]
					var b2: int = pal[pixel_index_2 * 4 + 2]
					var a2: int = pal[pixel_index_2 * 4 + 3]
					image.set_pixel(x + 1, y, Color(r2 / 255.0, g2 / 255.0, b2 / 255.0, a2 / 255.0))

		return image
	elif type == 9:
		var image: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		
		pal = data.slice(0x14, 0x414)
		img_dat = data.slice(0x420)
		for y in range(h):
			for x in range(w):
				var pixel_index: int = img_dat[x + y * w]
				var r: int = pal[pixel_index * 4 + 0]
				var g: int = pal[pixel_index * 4 + 1]
				var b: int = pal[pixel_index * 4 + 2]
				var a: int = pal[pixel_index * 4 + 3]
				a = int((a / 128.0) * 255.0)
				
				image.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0))
		return image
		
	return Image.create_empty(1, 1, false, Image.FORMAT_L8)
	
	
func upac_parse(buff: PackedByteArray) -> Array:
	var f_name: String
	var f_size: int = 0
	var is_tm2: bool = false
	
	if buff.slice(0, 4).get_string_from_ascii() == "UPAC":
		var start_off: int = buff.decode_u32(8)
		var unk_flag: int = buff.decode_u32(0xC)
		if buff.slice(start_off + 8, start_off + 11).get_string_from_ascii() == "LZS":
			f_size = buff.decode_u32(start_off + 0xC)
			buff = ComFuncs.decompLZSS(buff.slice(start_off + 0x10), buff.size() - start_off - 0x10, f_size)
			if buff.slice(0, 4).get_string_from_ascii() == "TIM2":
				is_tm2 = true
		else:
			if buff.slice(start_off + 8, start_off + 12).get_string_from_ascii() == "TIM2":
				is_tm2 = true
				
	var buffer: Array
	buffer.append(is_tm2)
	buffer.append(f_size)
	buffer.append(buff)
	return buffer
	
	
func load_tim2_images_mod(data: PackedByteArray, fix_alpha: bool = true) -> Array[Image]:
	# don't move pic offset by 16 if more than 1 image
	# swizzled palette detection
	# update into ComFuncs if this is a sure way to detect swizzled palettes?
	
	var images: Array[Image] = []

	# Check magic
	if data.slice(0, 4).get_string_from_ascii() != "TIM2":
		push_error("Not a TIM2 file")
		return images

	var tm2_version: int = data.decode_u8(5)
	if tm2_version > 1:
		push_error("Unknown TIM2 version %02X" % tm2_version)
		return images
		
	var picture_count: int = data.decode_u16(6)
	if picture_count <= 0:
		push_error("No pictures found")
		return images

	var pic_offset: int = 0x10
	for p in range(picture_count):
		if tm2_version == 1: pic_offset += 0x70
		var total_size: int = data.decode_u32(pic_offset)
		var clut_size: int = data.decode_u32(pic_offset + 4)
		var img_size: int = data.decode_u32(pic_offset + 8)
		var header_size: int = data.decode_u16(pic_offset + 0x0C)
		var clut_colors: int = data.decode_u16(pic_offset + 0x0E)
		var pic_format: int = data.decode_u8(pic_offset + 0x10)
		var mipmap_count: int = data.decode_u8(pic_offset + 0x11)
		var clut_color_type: int = data.decode_u8(pic_offset + 0x12)
		var img_color_type: int = data.decode_u8(pic_offset + 0x13)
		var width: int = data.decode_u16(pic_offset + 0x14)
		var height: int = data.decode_u16(pic_offset + 0x16)

		var img_data_offset: int = pic_offset + header_size
		var clut_data_offset: int = img_data_offset + img_size

		# --- Palette (CLUT) ---
		var palette: Array[Color] = []
		if clut_size > 0:
			var pal_bytes: PackedByteArray = data.slice(clut_data_offset, clut_data_offset + clut_size)
			if clut_color_type & 128 == 0 and clut_colors == 256:
				pal_bytes = ComFuncs.unswizzle_palette(pal_bytes, 32)
				
			# Apply alpha correction ONLY for indexed formats
			if fix_alpha:
				match img_color_type:
					3, 5:
						for j in range(3, pal_bytes.size(), 4):
							var a: int = int((pal_bytes.decode_u8(j) / 128.0) * 255.0)
							pal_bytes.encode_u8(j, a)
							
			for i in range(clut_colors):
				var col: int = pal_bytes.decode_u32(i * 4)
				var r: int =  col        & 0xFF
				var g: int = (col >> 8)  & 0xFF
				var b: int = (col >> 16) & 0xFF
				var a: int = (col >> 24) & 0xFF
				palette.append(Color8(r, g, b, a))

		# --- Image decode ---
		var img: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)

		match img_color_type:
			1: 
				# 1: 16-bit A1B5G5R5  (bits: R=0..4, G=5..9, B=10..14, A=15)
				for y in range(height):
					for x in range(width):
						var idx: int = (y * width + x) * 2
						var px: int = data.decode_u16(img_data_offset + idx)
						var a1: int = (px >> 15) & 1
						var r5: int = (px >> 0) & 0x1F
						var g5: int = (px >> 5) & 0x1F
						var b5: int = (px >> 10) & 0x1F
						# expand 5->8 bits (better than <<3):
						var r: int = (r5 << 3) | (r5 >> 2)
						var g: int = (g5 << 3) | (g5 >> 2)
						var b: int = (b5 << 3) | (b5 >> 2)
						var a: int = 255 if a1 else 0
						img.set_pixel(x, y, Color8(r, g, b, a))
			2:  # 24-bit RGB888 -> bytes [R, G, B] per pixel
				for y in range(height):
					for x in range(width):
						var idx: int = (y * width + x) * 3
						var r: int = data.decode_u8(img_data_offset + idx + 0)
						var g: int = data.decode_u8(img_data_offset + idx + 1)
						var b: int = data.decode_u8(img_data_offset + idx + 2)
						var a: int = 255
						img.set_pixel(x, y, Color8(r, g, b, a))
			3:  # 32-bit A8B8G8R8  -> bytes [R, G, B, A] in stream (little-endian)
				for y in range(height):
					for x in range(width):
						var col: int = data.decode_u32(img_data_offset + (y * width + x) * 4)
						var r: int =  col        & 0xFF
						var g: int = (col >> 8)  & 0xFF
						var b: int = (col >> 16) & 0xFF
						var a: int = (col >> 24) & 0xFF
						if fix_alpha: 
							a = int((a / 128.0) * 255.0)
						img.set_pixel(x, y, Color8(r, g, b, a))
			4:  # 4-bit indexed
				for y in range(height):
					for x in range(width):
						var byte: int = data.decode_u8(img_data_offset + ((y * width + x) >> 1))
						var idx: int = (byte & 0x0F) if (x & 1) == 0 else ((byte >> 4) & 0x0F)
						if idx < palette.size():
							img.set_pixel(x, y, palette[idx])
						else:
							img.set_pixel(x, y, Color(0, 0, 0, 1))
			5:  # 8-bit indexed
				for y in range(height):
					for x in range(width):
						var idx: int = data.decode_u8(img_data_offset + y * width + x)
						if idx < palette.size():
							img.set_pixel(x, y, palette[idx])
						else:
							img.set_pixel(x, y, Color(0, 0, 0, 1))
			_:
				push_error("Unsupported TIM2 image color type: %d" % img_color_type)

		images.append(img)

		# Move to next picture block
		pic_offset += total_size

	return images
	
	
func _on_load_exe_pressed() -> void:
	zero_load_exe.show()


func _on_zero_load_exe_file_selected(path: String) -> void:
	exe_path = path


func _on_load_pac_pressed() -> void:
	zero_load_pac.show()


func _on_zero_load_pac_file_selected(path: String) -> void:
	zero_load_folder.show()
	selected_file = path


func _on_zero_load_folder_dir_selected(dir: String) -> void:
	folder_path = dir


func _on_zero_load_tex_files_selected(paths: PackedStringArray) -> void:
	selected_texs = paths
	zero_load_folder.show()


func _on_load_tex_pressed() -> void:
	zero_load_tex.show()
