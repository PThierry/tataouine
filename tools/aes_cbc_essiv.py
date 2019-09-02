#! /usr/bin/env python
# -*- coding: utf-8 -*-

# Encrypt or decrypt in CBC-ESSIV a flat file

from common_utils import *
from crypto_utils import *


def PrintUsage():
    executable = os.path.basename(__file__)
    print("Error when executing %s\n\tUsage:\t%s keys_path algorithm=<AES|TDES> direction=<enc|dec> sector_size=<512|1024|2048|4096> secto_start_num file master_key" % (executable, executable))
    sys.exit(-1)

def derive_essiv_iv(key, sector_num, algo):
    if algo == "AES":
        sector_str = expand(inttostring(sector_num), 32, "LEFT") + "\x00"*(16-4)
        aes = local_AES.new(key, AES.MODE_ECB)
        return aes.encrypt(sector_str)
    elif algo == "TDES":
        sector_str = expand(inttostring(sector_num), 32, "LEFT") + "\x00"*(8-4)
        tdes = local_DES3.new(key[:24], DES3.MODE_ECB)
        return tdes.encrypt(sector_str)
    else:
        print("Unknown algorithm %s" % algo)
        sys.exit(-1)

if __name__ == '__main__':
    # Register Ctrl+C handler
    signal.signal(signal.SIGINT, handler)
    # Get the arguments
    if len(sys.argv) < 7:
        PrintUsage()
    keys_path = sys.argv[1]
    algorithm = sys.argv[2]
    direction = sys.argv[3]
    sector_size = int(sys.argv[4])
    sector_start = int(sys.argv[5])
    in_file = sys.argv[6]
    master_key = None
    if len(sys.argv) == 8:
        master_key = sys.argv[7]
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
        iv = derive_essiv_iv(master_key[32:], s, algorithm)
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
