# Writes an EXIF orientation into a JPEG, as a camera does: ImageMagick 7 writes none for an image it makes.
module ExifOrientation

  def self.write(path, code)
    entry = [0x0112, 3, 1, code, 0].pack('vvVvv')
    exif  = "Exif\0\0II".b + [42, 8, 1].pack('vVv') + entry + [0].pack('V')
    data  = File.binread(path)

    File.binwrite(path, data[0, 2] + "\xFF\xE1".b + [exif.bytesize + 2].pack('n') + exif + data[2..])
  end

end
