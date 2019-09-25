#! /usr/bin/env python
# -*- coding: utf-8 -*-

# Encrypt or decrypt in CBC-ESSIV a flat file

from common_utils import *
from crypto_utils import *


def PrintUsage():
    executable = os.path.basename(__file__)
    print("Error when executing %s\n\tUsage:\t%s keys_path algorithm=<AES|TDES> direction=<enc|dec> sector_size=<512|1024|2048|4096> sector_start_num SD_diverse file <master_key>" % (executable, executable))
    print("SD_diverse = SD card CID information in hex (CID register value obtained with command 2, on 128 bits as per SD standard). If SD_diverse=0, this will print more help to get it.")
    print("<master_key> = optional master key on 32 bytes (256 bits). If not provided, we use the AUTH token to get it")
    sys.exit(-1)

def derive_essiv_iv(key, sector_num, algo, SD_driverse):
    # Sanity check
    if len(SD_driverse) != 16:
        print("Bad SD CID length %d" % len(SD_driverse))
        sys.exit(-1)
    (hash_SD, _, _) = local_sha256(SD_diverse)    
    if algo == "AES":
        sector_str = expand(inttostring(sector_num), 32, "LEFT") + hash_SD[:(16-4)]
        aes = local_AES.new(key, AES.MODE_ECB)
        return aes.encrypt(sector_str)
    elif algo == "TDES":
        sector_str = expand(inttostring(sector_num), 32, "LEFT") + hash_SD[:(8-4)]
        tdes = local_DES3.new(key[:24], DES3.MODE_ECB)
        return tdes.encrypt(sector_str)
    else:
        print("Unknown algorithm %s" % algo)
        sys.exit(-1)

if __name__ == '__main__':
    # Register Ctrl+C handler
    signal.signal(signal.SIGINT, handler)
    # Get the arguments
    if len(sys.argv) < 8:
        PrintUsage()
    keys_path = sys.argv[1]
    algorithm = sys.argv[2]
    direction = sys.argv[3]
    sector_size = int(sys.argv[4])
    sector_start = int(sys.argv[5])
    sector_start = int(sys.argv[6])
    SD_diverse = sys.argv[6]
    in_file = sys.argv[7]
    master_key = None
    if len(sys.argv) == 9:
        master_key = sys.argv[8]
    if direction != "enc" and direction != "dec":
        print("Error: provided direction %s is not OK (must be 'enc' or 'dec')!" % direction)
        sys.exit(-1)
    if (sector_size != 512) and (sector_size != 1024) and (sector_size != 2048) and (sector_size != 4096):
        print("Error: provided sector size %d is not OK (must be 512, 1024, 2048 or 4096)!" % sector_size)
        sys.exit(-1)
    file_size = os.path.getsize(in_file)
    if(file_size % sector_size != 0):
        print("Error: file %s size %d is not a multiple of sector size %d!" % (in_file, file_size, sector_size))
        sys.exit(-1)
   
    # SD diversifier is either 128 bit long (i.e. 32 hex bytes), or 0 to tell that we need help to get it
    if SD_diverse == "0":
        # Explain how to get CID
        print("In order to get the CID of your SD card, please use a real SD card reader (USB to SD will not work as they")
        print("only show a mass storage device with no advanced SDIO capabilities). Once done, perform the following:")
        print("    - Under Linux: execute 'cat /sys/bus/mmc/devices/mmc0\:0007/cid' while adapting the mmc device. This")
        print("      should print a 128-bit value in hexadecimal (32 hexadecimal characters).")
        print("    - Under other OSes: the CID might appear in the peripherals panel details, or dedicated software can")
        print("      be used to retrieve it.")
        sys.exit(-1)
    else:
        if len(SD_diverse) != 32:
            print("Error: provided CID %s of size %d is not proper hex (must be 128 bits, i.e. 32 hex bytes)!" % (SD_diverse, len(SD_diverse)))
            sys.exit(-1)
        # Get binary from input
        SD_diverse = local_unhexlify(SD_diverse)

    if master_key == None:
        from token_utils import *  
        # Get the main encryption key
        card = connect_to_token("AUTH")
        # Ask for pet and user PIN
        pet_pin = get_user_input("Please provide AUTH PET pin:\n")
        user_pin = get_user_input("Please provide AUTH USER:\n")
        scp_auth = token_full_unlock(card, "auth", keys_path+"/AUTH/encrypted_platform_auth_keys.bin", pet_pin=pet_pin, user_pin=user_pin) # pet_pin="1234", user_pin="1234", force_pet_name_accept = True)
        master_key, sw1, sw2 = scp_auth.token_auth_get_key(user_pin)
        if (sw1 != 0x90) and (sw2 != 0x00):
            print("Error: can't get master key from AUTH token")
            sys.exit(-1)
    else:
        master_key = local_unhexlify(master_key)

    if len(master_key) != 64:
        print("Error: master key lenght %d != 64!" % len(master_key))
        sys.exit(-1)
   
    # Sanity check: second part should be SHA-256 of first part
    (hash_key, _, _) = local_sha256(master_key[:32])
    if hash_key != master_key[32:]:
        print("Error: master key is not consitent (computed hash of the key non conforming)")
        sys.exit(-1)
        
    in_fd = open(in_file, "r")
    out_fd = open(in_file+"_"+direction, "w")

    for s in range(file_size//sector_size):
        # Shift by the provided sector offset
        s = sector_start + s
        # Read the sector
        sector = in_fd.read(sector_size)
        # Derive the IV
        iv = derive_essiv_iv(master_key[32:], s, algorithm, SD_diverse)
	# Encrypt or decrypt the sector
        if algorithm == "AES":
            crypto = local_AES.new(master_key[:32], AES.MODE_CBC, iv=iv)
        elif algorithm == "TDES":
            crypto = local_DES3.new(master_key[:24], DES3.MODE_CBC, iv=iv)
        else:
            print("Error, unknown algorithm %s" % algorithm)
        if direction == "enc":
            ciphered_sector = crypto.encrypt(sector)
        elif direction == "dec":
            ciphered_sector = crypto.decrypt(sector)
        else:
            print("Error, unknown direction %s" % direction)
        out_fd.write(ciphered_sector)

in_fd.close()
out_fd.close()
